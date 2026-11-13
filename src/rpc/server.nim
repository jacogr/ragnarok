# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dispatcher-owned loopback WebSocket connections and publication handoffs.
##
## Each slot owns its upgrade, message assembly, reply and subscription queue. Reads
## pause while an output is pending so slow clients cannot accumulate replies. A
## fragmented message keeps its original deadline across control frames, and a slow
## write gets its own absolute deadline.
##
## A canonical worker lease pauses dispatch. The caller installs or resumes the
## selected view before serving chain queries again. Destruction and close release
## the socket owner and per-connection state.

import std/[assertions, nativesocket, oserrors, strutils, monotimes]
import std/posix/posix
import ../lib/socket_io
import std/http/httpmsg as http_msg
import std/http/httpparse as http_parse
import ./[wire, protocol, proof_requests]
import ./light_source
import ./wire_stream
import ./transport_bridge as transport
from ../codec/state/trie as state_trie import StateRoot
import ../chain/[parameters, genesis, provider]
import ../state/store
import ../state/accumulation/[chain as accumulation_chain, completion as accumulation_completion,
    finalization as accumulation_finalization, publication as accumulation_publication]
import ../state/accumulation/current/update as accumulation_current_update

const MaxConnections* = 8

# Each slot's strings own their data; no transport/native callback retains a pointer into them.
type
  Connection = object
    opened, upgraded, closing, fragmented: bool
    fd: cint
    stream: RpcWireStream
    streamWriting: bool
    input, output, message: string
    headScanner: http_parse.HeadScanner # Resumes the stock scan across partial reads.
    offset: int
    bridgeEpoch, retiredBridgeEpoch: uint64
    bridgeWaiting: bool
    bridgeGrant: transport.BridgeDispatch
    bridgeReply: transport.BridgeMessage
    session: RpcSession                 # Per-connection IDs and bounded notifications, released on disconnect.
    deadline, messageDeadline: int64
  RpcChainLease* = ref object ## Opaque host-only identity authorizing one chain pause; never shared with a worker.
    marker: uint8
  Server* = object ## Non-copyable listener; an exclusive chain pause retains sockets without exposing request contexts.
    httpTags: nil http_msg.HttpTags # One vocabulary for this listener’s synchronous parses.
    opened, proofs, transportMode: bool
    bridgeAddress: nil pointer
    proofCursor: int                # Fair bounded scan advances after each successfully claimed connection.
    lease: nil RpcChainLease
    fd: cint
    connections: array[MaxConnections, Connection]
    started: int64
    port, uiPort: uint16
    role: string
    light: RpcLightHead             # Distinct immutable partial source shares no complete provider state.
    lightDisk: bool
    chain: ChainView                # Retained immutable provider view shared by one dispatcher tick.
    identity: ChainIdentity # Fixed configured genesis identity is independent of selected/restarted history.
    parameters: ParameterResult     # Fixed-size owned configuration shared by all connections.

type RpcProofDispatch* = object ## Host-only routing retains a detached request namespace, never a canonical snapshot.
  index: int
  selection: RpcProofRequest

func valid*(dispatch: RpcProofDispatch): bool =
  ## Default routing tickets grant no connection delivery authority.
  dispatch.selection.valid

func proofRequest*(dispatch: RpcProofDispatch): RpcProofRequest {.requires: dispatch.valid.} =
  ## The host receives exact fixed selectors after the RPC tick activation has retired.
  dispatch.selection

type
  RpcAccumulationError* {.pure.} = enum ## Default/closed listeners and rejected state-chain adoption expose no child.
    Uninitialized, None, Unavailable, StaleView, ChainFailure
  RpcAccumulationResult* = object ## Only success retains the published child; failed adoption retains its actual selected cause.
    case status: RpcAccumulationError
    of None:
      completed: BlockSnapshot
    of ChainFailure:
      chainReason: AccumulationChainResult
    else:
      discard # Defaults and unavailable listeners carry no usable publication payload.

func error*(outcome: RpcAccumulationResult): RpcAccumulationError =
  ## Inspect publication status without exposing a mutable discriminator.
  outcome.status

func value*(outcome: RpcAccumulationResult): BlockSnapshot {.inline,
    requires: outcome.status == RpcAccumulationError.None.} =
  ## Retain only the exact child installed in both state and RPC history.
  outcome.completed

func chainFailure*(outcome: RpcAccumulationResult): AccumulationChainResult {.inline,
    requires: outcome.status == RpcAccumulationError.ChainFailure.} =
  ## Inspect only an actual failed state/chain adoption, preserving its nested guarded causes.
  outcome.chainReason

proc `=copy`*(destination: var Server, source: Server) {.error: "RPC Server owns socket descriptors".}
  ## Composite owner is explicitly non-copyable: copying slots would duplicate native descriptor ownership.

proc `=dup`*(source: Server): Server {.error.}
  ## Native listener and suspension ownership cannot be duplicated.

proc requireChainReleased(server: Server) {.requires: server.lease == nil.} =
  ## Retiring shared canonical aliases during worker execution is a host lifecycle defect.
  discard

proc `=wasMoved`*(server: var Server) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  server.opened = false
  server.transportMode = false
  server.bridgeAddress = nil
  server.fd = -1
  `=wasMoved`(server.lease)
  `=wasMoved`(server.role)
  `=wasMoved`(server.light)
  `=wasMoved`(server.chain)
  # Generated object/array hooks clear managed bytes but leave scalar descriptor flags intact.
  `=wasMoved`(server.httpTags)
  `=wasMoved`(server.connections)
  for slot in mitems(server.connections):
    # Every accepted descriptor belongs to the destination, including streaming files.
    slot.opened = false
    slot.fd = -1

proc `=destroy`*(server: Server) =
  ## ARC destruction closes descriptors only after every exclusive chain lease has ended.
  requireChainReleased(server)
  assert not server.transportMode, "closeTransport must retire the detached bridge before destruction"
  if server.opened and server.fd >= 0:
    # Default and detached instances never close stdin.
    discard posix.close(server.fd)
  for slot in server.connections: # Slots are owned solely by this server, without reference cycles.
    slot.stream.stop()
    when declared(rpcDirectTestSockets):
      if slot.opened and slot.bridgeEpoch == 0 and slot.fd >= 0:
        discard posix.close(slot.fd)

  # Custom destruction must release dynamic ARC fields as well as native descriptors.
  `=destroy`(server.httpTags)
  `=destroy`(server.connections)
  `=destroy`(server.role)
  `=destroy`(server.light)
  `=destroy`(server.chain) # The retained state map is an ARC owner too.
  `=destroy`(server.lease)

func availableForStart*(server: Server): bool =
  ## Scalar startup admission never replaces another live listener or graph lease.
  not server.opened and server.lease == nil

func chainPaused*(server: Server): bool =
  ## Scalar host-only observation does not copy a canonical snapshot.
  server.lease != nil

proc pauseChain*(server: var Server): nil RpcChainLease =
  ## Freeze all RPC canonical access between ticks; an existing lease grants no second token.
  if server.lease != nil: return nil # Nested callers cannot recover another owner's resume authority.
  server.lease = RpcChainLease(marker: 1)
  server.lease

proc resumeChain*(server: var Server, lease: nil RpcChainLease): bool =
  ## Resume only the exact retained host token after worker collection or join has ended all ARC access.
  if lease == nil or server.lease != lease: return false # Foreign/default/stale authority is inert.
  server.lease = nil
  true

proc close(slot: var Connection) =
  ## Retire one slot exactly once and release queued data; close is not retried after EINTR.
  slot.stream.stop() # Joining happens after completion, so one stalled writer cannot block a tick.
  slot.streamWriting = false
  when declared(rpcDirectTestSockets):
    if slot.opened and slot.bridgeEpoch == 0 and slot.fd >= 0:
      discard posix.close(slot.fd)
  if slot.bridgeEpoch != 0:
    slot.retiredBridgeEpoch = slot.bridgeEpoch # The next bridge tick retires only this old generation.
  slot.bridgeEpoch = 0
  slot.bridgeWaiting = false
  slot.bridgeGrant = default(transport.BridgeDispatch)
  slot.bridgeReply = default(transport.BridgeMessage)
  slot.opened = false
  slot.session = default(RpcSession) # Reused connection slots cannot inherit subscriptions or pending updates.
  slot.input = ""; slot.output = ""; slot.message = ""
  slot.headScanner = default(http_parse.HeadScanner) # The next client starts scanning its own input at zero.
  slot.messageDeadline = 0
  slot.offset = 0; slot.upgraded = false; slot.closing = false; slot.fragmented = false

proc close*(server: var Server) {.requires: server.lease == nil.} =
  ## Request retirement for every stream before joining any of them.
  if server.transportMode: return # The caller must retire the independently owned bridge.
  for slot in mitems(server.connections):
    # Release accepted sockets before listener.
    slot.close()
  for slot in mitems(server.connections):
    slot.stream = default(RpcWireStream) # Every stream has already received its stop request.
  if server.opened and server.fd >= 0:
    discard posix.close(server.fd)
  server.bridgeAddress = nil
  server.httpTags = nil # Release the vocabulary after closing request slots.
  server.opened = false
  server.light = default(RpcLightHead)
  server.lightDisk = false
  server.proofs = false # A restarted listener requires an explicit canonical host binding again.

proc enableStateProofs*(server: var Server): bool =
  ## Only a live unpaused listener may advertise the host's managed proof binding.
  if not server.opened or server.lease != nil: return false
  server.proofs = true
  true

proc takeStateProofRequest*(server: var Server): RpcProofDispatch =
  ## Claim one detached selector by rotating across the live connection slots.
  ## Run after RPC tick and outside the canonical lease, so no request view survives
  ## worker admission. Completion remains tied to the original request namespace,
  ## even when the transport reuses a slot or descriptor.
  if not server.opened or not server.proofs or server.lease != nil:
    return default(RpcProofDispatch)
  for step in 0..<MaxConnections:
    let index = (server.proofCursor + step) mod MaxConnections
    if server.connections[index].opened and server.connections[index].upgraded and
        not server.connections[index].closing:
      let selected = server.connections[index].session.takeStateProofRequest()
      if selected.valid:
        server.proofCursor = (index + 1) mod MaxConnections
        return RpcProofDispatch(index: index, selection: selected)
  default(RpcProofDispatch) # No request retains no routing or selection authority.

proc finishStateProofImport*(server: var Server, dispatch: RpcProofDispatch,
    root: StateRoot, knownFacts: int, failure = ""): bool =
  ## Deliver actual adoption/publication outcomes only after native/CPU lease release and to the exact live connection namespace.
  if not server.opened or server.lease != nil or not dispatch.valid or
      not dispatch.selection.isImport or dispatch.index < 0 or dispatch.index >=
      MaxConnections: return false # No unselected or still-borrowed context is read.
  let index = dispatch.index
  if not server.connections[index].opened or not server.connections[index].upgraded or
      server.connections[index].closing: return false # Disconnect cannot resurrect a request.
  if not server.connections[index].session.completeStateProofImport(dispatch.selection, root,
      knownFacts, failure):
    server.connections[index].close() # A slow originating consumer cannot roll back adopted storage.
    return false
  true

proc finishStateProof*(server: var Server, dispatch: RpcProofDispatch, root: StateRoot,
    wire: openArray[byte], failure = ""): bool =
  ## Deliver only after lease release; connection-local namespaces suppress stale/reset completions.
  if not server.opened or server.lease != nil or not dispatch.valid or dispatch.index < 0 or
      dispatch.index >= MaxConnections: return false
  let index = dispatch.index
  if not server.connections[index].opened or not server.connections[index].upgraded or
      server.connections[index].closing: return false
  if not server.connections[index].session.completeStateProof(dispatch.selection, root, wire, failure):
    server.connections[index].close() # Byte/count overflow retires only the slow originating consumer.
    return false
  true

proc initializeContext(server: var Server, port: uint16, role: string,
    parameters: ParameterResult, genesis: GenesisResult, uiPort: uint16, identity: ChainIdentity) =
  ## Both socket and detached transports retain exactly the same dispatcher-owned query context.
  server.started = getMonoTime().ticks div 1_000_000
  server.port = port
  server.uiPort = uiPort
  server.role = role
  server.parameters = parameters
  server.identity = identity
  server.light = default(RpcLightHead)
  server.lightDisk = false
  server.chain = genesisView(genesis)

proc start*(server: var Server, port: uint16, role: string,
    parameters = unavailableParameters(), genesis = unavailableGenesis(),
        uiPort: uint16 = 0, identity = default(ChainIdentity)): bool =
  ## Bind loopback only; port zero disables RPC. Startup failure is reported to the peer CLI.
  if server.opened or server.lease != nil:
    # A second or paused start cannot leak or replace a live listener.
    return false
  if port == 0:
    # Disabled by default, with no allocation or clock work.
    return true
  server.fd = listenLoopback(port, cint(MaxConnections))
  if server.fd < 0: return false # Failed setup closes its own descriptor.
  server.opened = true
  server.initializeContext(port, role, parameters, genesis, uiPort, identity)
  true

proc startTransport*(server: var Server, port: uint16, role: string,
    parameters = unavailableParameters(), genesis = unavailableGenesis(),
    uiPort: uint16 = 0, identity = default(ChainIdentity)): bool =
  ## Initialize the real RPC dispatcher without a native listener; the caller owns transport IO and bridge lifetime.
  if not server.availableForStart: return false
  server.fd = -1
  server.opened = true
  server.transportMode = true
  server.bridgeAddress = nil
  for slot in mitems(server.connections):
    slot.retiredBridgeEpoch = 0 # A restarted dispatcher begins after its previous bridge was retired.
  server.initializeContext(port, role, parameters, genesis, uiPort, identity)
  true

proc closeTransport*(server: var Server, bridge: var transport.RpcTransportBridge): bool =
  ## Retire detached mailboxes in bounded work before canonical owners; IO task joining remains the caller's duty.
  if server.lease != nil: return false
  if not server.transportMode: return not server.opened
  if server.bridgeAddress != nil and server.bridgeAddress != cast[pointer](
      addr bridge): return false
  bridge.beginStop() # Admission cannot race a completed retirement scan.
  var retired = true
  for index in transport.BridgeIndex.low..transport.BridgeIndex.high:
    # Busy mailboxes are retried on a later dispatcher turn rather than blocking shutdown.
    var connection = default(transport.BridgeTicket)
    let observed = bridge.snapshot(index, connection)
    if observed == transport.Busy:
      retired = false
    elif observed == transport.Ready and bridge.close(connection) != transport.Ready:
      retired = false # A changed generation is observed again on the next bounded close turn.
  if not retired: return false
  server.transportMode = false
  server.close()
  true

# Queue only after a successful publication; overflow retires one consumer without rolling back the head.
proc start*(server: var Server, port: uint16, role: string,
    parameters: ParameterResult, view: ChainView, uiPort: uint16 = 0,
    identity = default(ChainIdentity)): bool =
  ## Startup binds the whole restored local history/finality before any dispatcher can observe the listener.
  let head = view.bestBlock
  if head.error != GenesisError.None or not parameters.ok or
      parameters.value.encodeParameters != head.value.chainParameters.encodeParameters:
    return false # No live socket may be opened for a mismatched or absent restored view.
  if not server.start(port, role, parameters, head, uiPort, identity): return false
  server.chain = view
  true

proc queueBestUpdates(server: var Server, child: BlockSnapshotResult) =
  ## Queue head updates for usable WebSocket clients, closing only overflowing subscribers.
  for slot in mitems(server.connections):
    if slot.opened and slot.upgraded and not slot.closing: # Only usable WS connections receive events.
      if not slot.session.queueChainUpdates(child):
        slot.close() # Disconnect only the overflowing consumer; never drop events or reject the accepted head.

proc publishBlock*(server: var Server, child: BlockSnapshotResult): ViewAdvanceError =
  ## Publish a caller-validated direct child between ticks on the same dispatcher thread.
  ## Closed/disabled listeners and missing seeds return Uninitialized; other failures preserve the
  ## current view and forward advanceView's reason. Success replaces the chain and queues subscription updates,
  ## preserving sockets, queued replies and startup parameters unless a subscriber FIFO overflows.
  ## Serialized replies keep their original view's bytes. Incomplete incoming
  ## requests observe the view of the tick that finishes processing them.
  if not server.opened or server.lease != nil:
    return ViewAdvanceError.Uninitialized # Shutdown cannot be bypassed by publishing another snapshot.
  let update = server.chain.advanceView(child)
  if update.error != ViewAdvanceError.None:
    return update.error # Never install a partial or rejected history.
  server.chain = update.value
  server.queueBestUpdates(child)
  ViewAdvanceError.None

proc publishAccumulation*(server: var Server, state: var StateStore,
    source: PreparedFinalAccumulation, limits: AccumulationCompositionLimits): RpcAccumulationResult =
  ## Adopt state and this server's history together on the dispatcher thread, then queue accepted best-head events.
  ## Refusal preserves state, history, pending replies and subscription queues. Overflow after success only disconnects its consumer.
  if not server.opened or server.lease != nil:
    return RpcAccumulationResult(status: RpcAccumulationError.Unavailable) # Closed/disabled listeners authorize no state or source work.
  let adopted = applyAccumulationChain(state, server.chain, source, limits)
  if adopted.error != AccumulationChainError.None:
    return RpcAccumulationResult(status: RpcAccumulationError.ChainFailure,
      chainReason: adopted) # Private composition/capture/append failure sends no subscriber events.
  server.queueBestUpdates(server.chain.bestBlock) # Both handles already own the accepted child before any notification work.
  RpcAccumulationResult(status: RpcAccumulationError.None, completed: adopted.value)

proc publishAccumulation*(server: var Server, state: var StateStore, view: var ChainView,
    source: PreparedFinalAccumulation, limits: AccumulationCompositionLimits): RpcAccumulationResult =
  ## Join an application-owned state/history pair only while RPC retains the same entire selected view.
  ## Publish all three handles before queue work; refusal preserves histories, finality and pending events.
  if not server.opened or server.lease != nil:
    return RpcAccumulationResult(status: RpcAccumulationError.Unavailable) # An unavailable listener never triggers a silent fallback.
  if not sameChainView(server.chain, view):
    return RpcAccumulationResult(status: RpcAccumulationError.StaleView) # Match history, exact map owners, profiles and finality before hashing.
  let adopted = applyAccumulationChain(state, view, source, limits)
  if adopted.error != AccumulationChainError.None:
    return RpcAccumulationResult(status: RpcAccumulationError.ChainFailure,
      chainReason: adopted) # The application and RPC owners still retain their complete original views.
  server.chain = view # State and application view already own this child; no fallible work precedes the third replacement.
  server.queueBestUpdates(server.chain.bestBlock)
  RpcAccumulationResult(status: RpcAccumulationError.None, completed: adopted.value)

proc canInstallPreparedAccumulation*(server: Server, state: StateStore, view: ChainView,
    prepared: PreparedChainUpdate, lease: nil RpcChainLease = nil): bool =
  ## Preflight exact canonical/RPC history and optional exclusive lease before durability begins.
  server.opened and server.lease == lease and canInstallChainUpdate(state, view, prepared) and
    sameChainView(server.chain, view)

proc installPreparedAccumulation*(server: var Server, state: var StateStore, view: var ChainView,
    prepared: PreparedChainUpdate, lease: nil RpcChainLease = nil) {.requires:
      canInstallPreparedAccumulation(server, state, view, prepared, lease).} =
  ## Install existing immutable handles before bounded subscriber work, without repeating composition/capture.
  ## Exclusive lease authority, when supplied, remains held until its owner explicitly resumes RPC.
  installChainUpdate(state, view, prepared)
  server.chain = view
  server.queueBestUpdates(server.chain.bestBlock) # Subscriber refusal/overflow cannot roll back the installed head.

proc canInstallPreparedAccumulation*(server: Server, state: StateStore, view: ChainView,
    prepared: PreparedCurrentChainUpdate, lease: nil RpcChainLease = nil): bool =
  ## Current opaque updates require the identical canonical/RPC history and exact optional exclusive lease before durability.
  server.opened and server.lease == lease and canInstallCurrentChainUpdate(state, view,
      prepared) and
    sameChainView(server.chain, view)

proc installPreparedAccumulation*(server: var Server, state: var StateStore, view: var ChainView,
    prepared: PreparedCurrentChainUpdate, lease: nil RpcChainLease = nil) {.requires:
      canInstallPreparedAccumulation(server, state, view, prepared, lease).} =
  ## Install all current immutable owners before bounded subscriber work; retain any exclusive lease until explicit resume.
  installCurrentChainUpdate(state, view, prepared)
  server.chain = view
  server.queueBestUpdates(server.chain.bestBlock) # Subscriber refusal cannot roll back the already installed current head.

proc queueFinalizedUpdates(server: var Server) =
  ## All canonical/RPC owners already hold the selected finality before subscriber queue work.
  for slot in mitems(server.connections):
    if slot.opened and slot.upgraded and not slot.closing:
      if not slot.session.queueChainUpdates(server.chain.finalizedBlock, finalized = true):
        slot.close() # Finality still advances; only the slow consumer is disconnected.

proc publishFinalized*(server: var Server, hash: BlockHash): ViewFinalizeError =
  ## Record caller-certified finality without verifying consensus; repeated selections remain silent.
  if not server.opened or server.lease != nil: return ViewFinalizeError.Uninitialized
  let update = server.chain.finalizeView(hash)
  if update.error != ViewFinalizeError.None: return update.error
  let previous = server.chain.finalizedBlock
  if previous.error == GenesisError.None:
    if array[32, byte](previous.value.blockHash) == array[32, byte](hash):
      return ViewFinalizeError.None # Idempotent publication never duplicates subscription events.
  server.chain = update.value
  server.queueFinalizedUpdates()
  ViewFinalizeError.None

proc publishFinalized*(server: var Server, view: var ChainView,
    hash: BlockHash): ViewFinalizeError =
  ## Join only identical complete histories/finality; failures preserve both owners and pending events.
  if not server.opened or server.lease != nil: return ViewFinalizeError.Uninitialized
  if not sameChainView(server.chain, view): return ViewFinalizeError.StaleView
  let update = view.finalizeView(hash)
  if update.error != ViewFinalizeError.None: return update.error
  let previous = view.finalizedBlock
  let repeated = previous.error == GenesisError.None and
    array[32, byte](previous.value.blockHash) == array[32, byte](hash)
  view = update.value
  server.chain = view # Both assignments precede subscriber serialization or disconnection work.
  if not repeated: server.queueFinalizedUpdates()
  ViewFinalizeError.None

proc reject(slot: var Connection, code: int, now: int64) =
  ## Queue a bounded close frame, then allow only its partial writes until the absolute deadline.
  let payload = $char(code shr 8) & $char(code and 255)
  slot.output = frame(payload, 8)
  slot.offset = 0
  slot.closing = true
  slot.deadline = now + 5000

proc processHead(slot: var Connection, header: string, tags: http_msg.HttpTags, now: int64,
    uiPort: uint16) =
  ## The task supplies a complete head. Upgrade selectors remain dispatcher policy.
  let response = upgrade(header, uiPort, tags)
  if response.len == 0:
    slot.close() # Invalid upgrades close without dispatching buffered frames.
    return
  slot.output = response
  slot.upgraded = true
  slot.deadline = now + 5000

proc processFrame(slot: var Connection, parsed: FrameResult, info: ClientInfo, now: int64) =
  ## Apply control and message-assembly policy to one detached framing result.
  if parsed.status != complete:
    slot.reject(1002, now)
    return
  case parsed.opcode
  of 8: # A close body is either empty or a legal status code followed by UTF-8 text.
    let payload = parsed.payload
    if payload.len == 1:
      slot.reject(1002, now)
      return
    if payload.len >= 2:
      let code = ord(payload[0]) * 256 + ord(payload[1])
      if not (code in [1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014] or
          code in 3000..4999): slot.reject(1002, now); return
      if not validUtf8(payload[2..^1]):
        slot.reject(1007, now)
        return
    slot.output = frame(payload, 8); slot.closing = true # Echo valid close and retire after delivery.
  of 9:
    # Ping payload is echoed exactly in an unmasked pong.
    slot.output = frame(parsed.payload, 10)
  of 10:
    # Unsolicited pongs are allowed and carry no application data.
    discard
  of 2:
    # JSON-RPC messages use text frames only.
    slot.reject(1003, now)
    return
  of 0, 1:
    if (parsed.opcode == 0 and not slot.fragmented) or (parsed.opcode == 1 and slot.fragmented):
      slot.reject(1002, now); return # Continuations cannot start messages or overlap existing ones.
    if parsed.payload.len > MaxMessage - slot.message.len:
      slot.reject(1009, now)
      return
    if not slot.fragmented:
      # Ping/pong cannot extend fragmented-message lifetime.
      slot.messageDeadline = now + 5000
    slot.message.add(parsed.payload)
    slot.fragmented = not parsed.final
    if parsed.final: # UTF-8 is checked across the assembled message, allowing splits inside code points.
      if not validUtf8(slot.message):
        slot.reject(1007, now)
        return
      let response = respond(slot.message, info, slot.session)
      slot.message = ""
      slot.messageDeadline = 0
      if response.len > 0:
        # Notifications have no response frame.
        slot.output = frame(response)
  else:
    # Decoder already excludes reserved opcodes.
    slot.reject(1002, now)
    return
  slot.offset = 0
  if slot.output.len > 0:
    # A slow consumer gets one absolute write budget.
    slot.deadline = now + 5000
  elif slot.input.len == 0 and not slot.fragmented:
    # Idle keepalive window.
    slot.deadline = now + 30000

when declared(rpcDirectTestSockets):
  proc process(slot: var Connection, tags: http_msg.HttpTags, info: ClientInfo, now: int64,
      uiPort: uint16 = 0) =
    ## Direct-descriptor fixtures use the same upgrade and frame policy synchronously.
    if not slot.upgraded:
      let headBytes = slot.headScanner.findHeadEnd(toOpenArray(slot.input, 0, slot.input.len - 1))
      if headBytes == http_parse.ParseIncomplete: return
      if headBytes < 0:
        slot.close()
        return
      let header = slot.input.substr(0, headBytes - 1)
      slot.input = slot.input.substr(headBytes)
      slot.processHead(header, tags, now, uiPort)
    else:
      let parsed = decodeFrame(slot.input)
      if parsed.status == incomplete: return
      if parsed.status == complete: slot.input = slot.input[parsed.consumed..^1]
      slot.processFrame(parsed, info, now)

proc tick*(server: var Server, peers: uint32) =
  ## One accept, one input handoff and one write handoff per slot per dispatcher turn.
  if not server.opened or server.lease != nil or server.transportMode:
    # Default peer operation does no additional syscall or clock work.
    return
  let existingTags = server.httpTags
  let tags: http_msg.HttpTags =
    if existingTags != nil:
      existingTags # A running listener reuses its vocabulary.
    else:
      let vocabulary = http_msg.newHttpTags()
      server.httpTags = vocabulary # Seed the vocabulary once before serving requests.
      vocabulary
  pollRpcStreams()
  for slot in mitems(server.connections):
    slot.stream.pump()
    if slot.stream.finished:
      slot.close()
      slot.stream = default(RpcWireStream)
  let now = getMonoTime().ticks div 1_000_000
  let accepted = acceptSocket(server.fd, nil, nil)
  if accepted >= 0: # Capacity pressure closes only the newly accepted socket.
    var free = -1
    for i in 0..<MaxConnections:
      if not server.connections[i].opened and not server.connections[i].stream.active:
        # At most one admission per dispatcher turn.
        free = i
        break
    if free < 0 or not nonblocking(accepted):
      discard posix.close(accepted)
    elif server.connections[free].stream.start(accepted):
      server.connections[free].fd = -1
      server.connections[free].opened = true
      server.connections[free].deadline = now + 5000
    else:
      discard posix.close(accepted)
  let info = ClientInfo(uptimeMs: now - server.started, peers: peers, role: server.role,
      port: server.port, proofs: server.proofs, parameters: server.parameters, chain: server.chain,
      light: server.light, lightDisk: server.lightDisk,
      identity: server.identity,
      occupiedBytes: getOccupiedMem(), reservedBytes: getTotalMem())
  for slot in mitems(server.connections): # Fixed capacity bounds per-turn work and memory.
    if not slot.opened or slot.bridgeEpoch != 0:
      continue
    # A partial frame in the worker uses its own receive deadline instead of
    # the dispatcher idle window. Upgrade, write and fragment budgets still apply.
    if (slot.fragmented and now >= slot.messageDeadline) or
        (now >= slot.deadline and (not slot.upgraded or slot.streamWriting or
          slot.closing or not slot.stream.hasBufferedInput)):
      slot.close()
      continue
    if slot.streamWriting:
      if slot.stream.writing: continue
      slot.streamWriting = false
      if slot.closing:
        slot.close()
        continue
      if slot.input.len == 0 and not slot.fragmented:
        slot.deadline = now + 30000
    # FIN is published only after the final framing result has been taken.
    let inputEnded = slot.stream.inputEnded
    if slot.output.len == 0 and not slot.closing:
      if slot.stream.active:
        var input = default(WireInput)
        if slot.stream.takeInput(input):
          case input.kind
          of BadHead: slot.close() # An oversized upgrade cannot reach HTTP policy.
          of UpgradeHead: slot.processHead(input.head, tags, now, server.uiPort)
          of ClientFrame: slot.processFrame(input.frame, info, now)
      else:
        when declared(rpcDirectTestSockets):
          # Directly injected descriptors are used by the native dispatcher fixtures.
          # The same bounded lookahead applies when the fixture owns raw reads.
          if slot.input.len < max(MaxHeader, MaxMessage + MaxClientFrameHeader):
            var bytes = default(array[4096, char])
            let count = receive(slot.fd, addr bytes[0], csize_t(bytes.len), 0)
            if count == 0 or (count < 0 and not retryableSocketError(osLastError())):
              slot.close()
              continue
            if count > 0:
              if slot.input.len == 0 and not slot.fragmented and slot.upgraded:
                slot.deadline = now + 5000
              for i in 0..<count: slot.input.add(bytes[i])
          slot.process(tags, info, now, server.uiPort)
    if slot.opened and not slot.closing and slot.output.len == 0:
      let update = slot.session.nextUpdate()
      if update.len > 0:
        slot.output = frame(update) # Request replies precede queued notifications on this connection.
        slot.offset = 0
        slot.deadline = min(slot.deadline, now + 5000) # Notifications cannot extend a partial input deadline.
    if not slot.opened:
      continue
    if slot.output.len == 0:
      # Orderly input EOF leaves the writer alive until pending replies retire.
      if inputEnded: slot.close()
      continue
    if slot.stream.active:
      slot.streamWriting = slot.stream.send(slot.output)
      continue
    when declared(rpcDirectTestSockets):
      let written = writePending(slot.fd, slot.output, slot.offset)
      if written == WriteComplete: # All response bytes were handed to the kernel.
        slot.output = ""; slot.offset = 0
        if slot.closing:
          slot.close()
        elif slot.input.len == 0 and not slot.fragmented:
          slot.deadline = now + 30000
      elif written == WriteFailed:
        # A zero-progress or permanently failed send cannot spin indefinitely.
        slot.close()

proc startLight*(server: var Server, port: uint16, role: string, parameters: ParameterResult,
    head: RpcLightHead, disk: bool, uiPort: uint16 = 0,
    identity = default(ChainIdentity)): bool =
  ## Bind the existing loopback transport to independent light metadata without retaining a complete ChainView.
  if not head.valid: return false # A default source never advertises a zero root.
  if not server.start(port, role, parameters, unavailableGenesis(), uiPort,
      identity): return false # Existing descriptor/port/lease checks remain authoritative.
  if port != 0:
    server.light = head # No dispatcher can observe the listener until this startup activation retires.
    server.lightDisk = disk
  true

proc canInstallLightHead*(server: Server, expected: RpcLightHead): bool =
  ## Exact immutable source incarnation includes proof knowledge, unlike equal header/root metadata alone.
  server.opened and server.lease == nil and sameRpcLightHead(server.light, expected)

proc installLightHead*(server: var Server, expected, target: RpcLightHead): bool =
  ## A preflighted host installs only after actual worker collection/join; no IO or proof verification runs here.
  if not target.valid or not server.canInstallLightHead(
      expected): return false # Refuse stale/foreign/paused source without changing RPC metadata.
  server.light = target
  true

proc bindTransportSlot(slot: var Connection, connection: transport.BridgeTicket) =
  ## A reservation may follow slot reuse after snapshot; bind sessions to its actual generation.
  if slot.bridgeEpoch != connection.generation:
    slot.close()
    slot.bridgeEpoch = connection.generation
    slot.opened = true
    slot.upgraded = true
    slot.fd = -1

proc dispatchTransport*(server: var Server, bridge: var transport.RpcTransportBridge,
    peers: uint32): int =
  ## One bounded request/frame per slot; no worker receives ClientInfo, RpcSession or canonical aliases.
  ## A lease refusal happens before constructing a query context or inspecting session owners.
  result = 0
  if not server.opened or not server.transportMode or server.lease != nil or bridge.stopping(): return 0
  let address = cast[pointer](addr bridge)
  if server.bridgeAddress == nil: server.bridgeAddress = address
  if server.bridgeAddress != address: return 0
  let now = getMonoTime().ticks div 1_000_000
  let info = ClientInfo(uptimeMs: now - server.started, peers: peers, role: server.role,
    port: server.port, proofs: server.proofs, parameters: server.parameters, chain: server.chain,
    light: server.light, lightDisk: server.lightDisk, identity: server.identity,
    occupiedBytes: getOccupiedMem(), reservedBytes: getTotalMem())
  for index in transport.BridgeIndex.low..transport.BridgeIndex.high:
    # Each connection has its own credit; a blocked writer cannot consume another slot's turn.
    var connection = default(transport.BridgeTicket)
    let observed = bridge.snapshot(index, connection)
    if observed == transport.Busy: continue
    if observed == transport.Empty:
      server.connections[index].close()
      continue
    let epoch = connection.generation
    if server.connections[index].retiredBridgeEpoch == epoch:
      discard bridge.close(connection) # Publication overflow or a terminal request retires this generation.
      continue
    server.connections[index].bindTransportSlot(connection)
    if server.connections[index].bridgeWaiting:
      # A busy commit retains the already serialized response; requests must not execute twice.
      let committed = bridge.commit(server.connections[index].bridgeGrant,
        server.connections[index].bridgeReply)
      if committed == transport.Busy: continue
      server.connections[index].bridgeWaiting = false
      if committed != transport.Ready: server.connections[index].close()
      continue
    var grant = default(transport.BridgeDispatch)
    var incoming = default(transport.BridgeMessage)
    let reserved = bridge.reserve(index, grant, incoming)
    if reserved == transport.Full:
      discard bridge.close(connection) # Exhausted reservation sequences never wrap into old authority.
      server.connections[index].close()
      continue
    if reserved != transport.Ready: continue
    server.connections[index].bindTransportSlot(grant.ticket)
    if server.connections[index].closing:
      discard bridge.close(connection) # The close frame has completed before its credit becomes available.
      server.connections[index].close()
      continue
    var outgoing = default(transport.BridgeMessage)
    case incoming.kind
    of transport.Text:
      let response = respond(incoming.payload, info, server.connections[index].session)
      if response.len > 0: outgoing = transport.BridgeMessage(kind: transport.Text,
          payload: response)
    of transport.Ping:
      outgoing = transport.BridgeMessage(kind: transport.Pong, payload: move(incoming.payload))
    of transport.Close:
      outgoing = transport.BridgeMessage(kind: transport.Close, code: incoming.code,
        payload: move(incoming.payload))
    of transport.Binary:
      outgoing = transport.BridgeMessage(kind: transport.Close, code: 1003)
    of transport.Pong, transport.None:
      discard # Pongs and turns without a request leave notification delivery eligible.
    if outgoing.kind == transport.None:
      let update = server.connections[index].session.nextUpdate()
      if update.len > 0: outgoing = transport.BridgeMessage(kind: transport.Text, payload: update)
    if outgoing.kind == transport.Close: server.connections[index].closing = true
    let committed = bridge.commit(grant, outgoing)
    if committed == transport.Busy:
      server.connections[index].bridgeWaiting = true
      server.connections[index].bridgeGrant = grant
      server.connections[index].bridgeReply = move(outgoing)
    elif committed != transport.Ready:
      server.connections[index].close() # A stale reservation never delivers into a replacement session.
    inc result
