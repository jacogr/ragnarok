# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One non-copyable owner for telemetry, RPC, UI and optional explicitly configured canonical state.
## The peer dispatcher borrows individual fields only while this stack owner remains stable;
## transport callbacks must retire before close/destruction. A bounded chain snapshot is shared once.
## After starting preparation, explicitly close to join before any borrowed input or shared alias retires.

import std/[syncio, strutils, base64]
import ./options
import ./checkpoint_recovery
import ./handoff
import ./candidate
import ./block_input
import ./preparation_worker
import ./[checkpoint_identity, checkpoint_transfer, checkpoint_session, checkpoint_worker, checkpoint_file]
import ../codec/bounded
import ../codec/[block_codec, header]
import ./chain as application_chain
import ../state/[store, accumulation_finalization, accumulation_completion]
import ../chain/provider
import ../telemetry/[wire, client, chain]
import ../quic/transport
import ../rpc/[server, protocol]
import ../chain/[parameters, genesis]
import ../ui/server

type Services* = object ## Owns listeners/exporter; fields are borrowed by synchronous peer callbacks.
  rpc*: Server
  ui*: UiServer
  telemetry*: Client
  chainText: string
  canonical: ApplicationChain
  adoption: AccumulationHandoff
  worker: PreparationWorker
  checkpointExport: ApplicationCheckpointSession
  rpcLease: nil RpcChainLease
  preparing: bool
  started, chainRpc: bool

proc `=wasMoved`*(services: var Services) {.nodestroy, inline, requires: not services.started.} =
  ## Only closed aggregates may relocate; native workers and callback borrows require the original stable parent address.
  `=wasMoved`(services.checkpointExport)
  `=wasMoved`(services.worker)
  `=wasMoved`(services.rpcLease)
  `=wasMoved`(services.ui)
  `=wasMoved`(services.rpc)
  `=wasMoved`(services.telemetry)
  `=wasMoved`(services.chainText)
  `=wasMoved`(services.canonical)
  `=wasMoved`(services.adoption)

proc `=copy`*(destination: var Services, source: Services) {.error: "Application Services owns descriptors".}
proc `=dup`*(source: Services): Services {.error.}
  ## Composite ownership includes the stable worker and all listener lifetimes.
proc `=destroy`*(services: Services) =
  ## Retire partially configured owners and the shared snapshot even without explicit shutdown.
  `=destroy`(services.checkpointExport) # Explicit close joins the detached I/O child before aggregate destruction.
  `=destroy`(services.worker) # Explicit close must join before any shared chain alias retires.
  `=destroy`(services.rpcLease)
  `=destroy`(services.ui)
  `=destroy`(services.rpc)
  `=destroy`(services.telemetry)
  `=destroy`(services.chainText)
  `=destroy`(services.canonical)
  `=destroy`(services.adoption)

proc stopPreparation*(services: var Services) =
  ## Join and discard private execution before reopening canonical/RPC access; listeners and canonical state remain owned.
  services.worker.close()
  services.preparing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil

proc stopCheckpointExport*(services: var Services) =
  ## Join detached I/O outside callbacks and retain actual uncollected work/retirement uncertainty until explicit acknowledgement.
  services.checkpointExport.close()

proc close*(services: var Services) =
  ## Idempotent retirement happens after every dispatcher/native callback has ended its borrows.
  services.stopCheckpointExport() # Repeated close preserves the fixed joined-outcome journal.
  services.stopPreparation() # Join before releasing any canonical or listener alias.
  services.ui.close()
  services.rpc.close()
  services.telemetry.close()
  services.rpc = default(Server) # Server.close retires sockets; replacement also releases its retained history/configuration.
  services.adoption = default(AccumulationHandoff) # Retire pending or unacknowledged immutable owners on shutdown.
  services.canonical = default(ApplicationChain)
  services.started = false
  services.chainRpc = false
  services.chainText = ""

# Read at most limit+1 bytes; empty output means missing, empty or oversized configuration.
proc boundedFile(path: string, limit: int): string {.raises.} =
  result = ""
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return # No implicit file/default chain.
  defer: close(file) # All read outcomes retire the handle.
  var text = newString(limit + 1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore() # Commit the public string bulk-write API before reading or resizing.
  if count <= 0 or count > limit: return # Detect growth/oversize without unbounded readFile.
  text.setLen(count)
  result = move(text)

proc setupRpc(rpc: var Server, options: Options, role: string, text: string): bool =
  ## An explicit RPC chain must validate before opening the listener; missing configuration remains unavailable.
  var parameters = default(ParameterResult)
  var genesis = unavailableGenesis()
  if options.rpcPort() != 0 and options.chainPath().len > 0:
    parameters = configuredParameters(text)
    if not parameters.ok: return false # Fail startup rather than advertise a partial/default parameter set.
    genesis = configuredGenesis(text, parameters.value)
    if genesis.error == GenesisError.Invalid: return false # Reject an incomplete or malformed explicit genesis.
  rpc.start(options.rpcPort(), role, parameters, genesis, options.uiPort())

proc setupTelemetry(client: var Client, options: Options, certificate: string, port: uint16,
    ipv6: bool, text: string): bool {.raises.} =
  ## Build registration from explicit JIP-4 configuration and the actual local certificate/socket.
  if not options.telemetryEnabled(): return true # Absence is the default and requires no configuration.
  if text.len == 0: return false # Never invent a chain or use an implicit development network.
  let pem = boundedFile(certificate, 16384).strip()
  const beginMarker = "-----BEGIN CERTIFICATE-----"
  const endMarker = "-----END CERTIFICATE-----"
  # Reject overlapping/empty PEM markers before constructing the body slice.
  if pem.len < beginMarker.len + endMarker.len: return false
  if not pem.startsWith(beginMarker) or not pem.endsWith(endMarker): return false
  var body = ""
  # Permit PEM whitespace but reject noncanonical base64 through round-trip validation below.
  for character in pem[beginMarker.len..<pem.len - endMarker.len]:
    if character notin {' ', '\t', '\r', '\n'}: body.add(character)
  var der = base64.decode(body)
  if der.len == 0 or der.len > 8192 or base64.encode(der) != body: return false
  # The native extractor initializes all C fields before success; no C array object constructor is used.
  var fields {.noinit.}: CertFields
  # Reuse maintained X.509 extraction; public identity is copied, never read from a secret key.
  let derPointer = der.toCString()
  if parseCert(cast[ptr byte](derPointer), csize_t(der.len), addr fields) != 1 or
      fields.edKey != 1 or fields.keyLength != 32: return false
  var address = default(array[16, byte])
  if ipv6:
    address[15] = 1 # The proof peer binds only ::1 in its IPv6 modes.
  else:
    # JIP-3 represents IPv4 endpoints as IPv4-mapped IPv6 addresses.
    address[10] = 255
    address[11] = 255
    address[12] = 127
    address[15] = 1
  var identity = default(array[32, byte])
  # Copy C array elements individually into native Nim storage before crossing the API boundary.
  for i in 0..<32: identity[i] = fields.key[i]
  let parsed = chainMetadata(text, identity, address, port)
  if not parsed.ok: return false # Failed chain metadata cannot produce a registration.
  configure(client, options.telemetryEndpoint(), parsed.value)

proc startServices(services: var Services, options: Options, role: string,
    withState: bool, limits: StateStoreLimits, recovered: ApplicationChain): bool {.raises.} =
  ## Capture one bounded file and install the optional canonical owner before listeners become observable.
  if services.started or not options.valid(): return false # Repeat start cannot disturb an existing lifetime.
  services.chainText = boundedFile(options.chainPath(), MaxChainBytes)
  if withState:
    if recovered.chainView.retainedCount > 0:
      let configured = configuredParameters(services.chainText)
      let head = recovered.chainView.bestBlock.value
      if not configured.ok or configured.value.encodeParameters !=
          head.chainParameters.encodeParameters:
        services.close() # A trusted anchor must still match the complete explicitly selected chain profile.
        return false
      services.canonical = recovered # Preserve the exact restored map, inherited policy and one-head/unfinalized view.
    else:
      let seeded = initApplicationChain(services.chainText, limits)
      if seeded.error != ApplicationChainError.None:
        services.close() # A missing/refused seed cannot become a partial listener-only startup.
        return false
      services.canonical = seeded.value
  if not services.ui.start(options.uiPort(), options.devUiDirectory()):
    stderr.writeLine("Invalid UI listener or --dev-ui-dir")
    services.close() # Failed startup cannot retain a directory, seed or partially opened listener.
    return false
  var rpcReady = false
  if withState:
    let head = services.canonical.chainView.bestBlock
    let parameters = decodeParameters(head.value.chainParameters.encodeParameters)
    rpcReady = services.rpc.start(options.rpcPort(), role, parameters, head, options.uiPort())
  else:
    rpcReady = services.rpc.setupRpc(options, role,
        services.chainText) # Preserve legacy optional/unavailable genesis behavior.
  if not rpcReady:
    stderr.writeLine("Invalid RPC listener or --chain parameters")
    services.close() # RPC failures retire both the UI listener and the canonical owner.
    return false
  services.chainRpc = withState and options.rpcPort() != 0
  services.started = true
  true

proc start*(services: var Services, options: Options, role: string): bool {.raises.} =
  ## Select canonical startup only from validated explicit CLI policy; legacy commands retain optional genesis behavior.
  var limits = genesisStoreLimits()
  if options.stateEnabled:
    limits.writes = options.stateWrites # Fixed trie ceilings never imply a mutable budget.
    limits.writeValueBytes = options.stateWriteBytes
    return startServices(services, options, role, true, limits, default(ApplicationChain))
  startServices(services, options, role, false, limits, default(ApplicationChain))

proc start*(services: var Services, options: Options, role: string,
    limits: StateStoreLimits): bool {.raises.} =
  ## Explicitly enable canonical complete-state ownership, sharing the exact seed with optional RPC.
  startServices(services, options, role, true, limits, default(ApplicationChain))

proc startRecovered*(services: var Services, options: Options, role: string,
    recovered: ApplicationRecoveryResult): bool {.raises.} =
  ## Explicit component recovery preserves its caller-selected map policy, like the existing explicit-limits startup overload.
  ## CLI recovery must restore with its parsed policy before calling this entry point; no map policy is widened here.
  if services.started or not options.valid or not options.stateEnabled:
    return false # Failed/repeated admission must not read files or disturb active services.
  if recovered.error != ApplicationRecoveryError.None:
    return false # Refused/default recovery never falls back to configured genesis.
  startServices(services, options, role, true, genesisStoreLimits(), recovered.value)

func chainView*(services: Services): ChainView {.requires: not services.preparing.} =
  ## Return an immutable selected-history alias; default/closed/legacy services have no canonical head.
  services.canonical.chainView

proc startCheckpointExport*(services: var Services,
    path: string): ApplicationCheckpointFileError {.raises.} =
  ## Explicit host startup requires an active stable service owner; pending shutdown acknowledgement blocks worker restart.
  if not services.started: return ApplicationCheckpointFileError.Uninitialized
  services.checkpointExport.start(path)
proc checkpointExportPhase*(services: var Services): ApplicationCheckpointWorkerPhase =
  ## Bounded scalar polling performs no serialization, canonical graph access or file I/O.
  services.checkpointExport.phase
proc stageCheckpointExport*(services: var Services, prepared: var PreparedApplicationCheckpoint,
    limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Stage only independent bytes, including during an execution lease; refusal preserves the caller's sole owner.
  services.checkpointExport.stage(prepared, limit)
proc beginCheckpointExport*(services: var Services, ticket: ApplicationCheckpointTicket): bool =
  ## Explicit bounded dispatch authorizes a matching staged native publication.
  services.checkpointExport.begin(ticket)
proc cancelCheckpointExport*(services: var Services, ticket: ApplicationCheckpointTicket): bool =
  ## Cancel only unstarted matching work; possible publication outcomes stay observable.
  services.checkpointExport.cancel(ticket)
proc peekCheckpointExport*(services: var Services,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Fixed receipt observation retains acknowledgement capacity and never touches canonical state.
  services.checkpointExport.peek(ticket)
proc collectCheckpointExport*(services: var Services,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Host acknowledgement retires sole bytes only after native aliases have ended.
  services.checkpointExport.collect(ticket)
func checkpointShutdownPending*(services: Services): bool =
  ## A fixed actual joined receipt survives canonical/listener close and repeated aggregate cleanup.
  services.checkpointExport.shutdownPending
func checkpointShutdown*(services: Services): ApplicationCheckpointShutdown =
  ## Only a retained shutdown journal grants its exact operation and retirement outcomes.
  services.checkpointExport.shutdown
proc takeCheckpointShutdown*(services: var Services): ApplicationCheckpointShutdown =
  ## Explicit acknowledgement unblocks export restart without retrying or adopting a possibly published state.
  services.checkpointExport.takeShutdown()

proc checkpointIdentity*(services: Services): ApplicationCheckpointIdentityResult {.requires: not services.preparing.} =
  ## Capture fixed context only while canonical aliases are available; no file metadata supplies independent trust.
  captureApplicationCheckpointIdentity(services.canonical)
proc prepareCheckpoint*(services: Services, limit: ByteLimit): PreparedApplicationCheckpoint {.requires: not services.preparing.} =
  ## Explicit host-side serialization runs outside callbacks and before any detached I/O admission or execution lease.
  prepareApplicationCheckpoint(services.canonical, limit)

proc stateSnapshot*(services: Services): StateStoreResult[StateStoreSnapshot] {.requires:
    not services.preparing.} =
  ## Retain only immutable complete state independently of listener lifetime and future adoption.
  services.canonical.stateSnapshot

proc applyAccumulation*(services: var Services, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): ApplicationChainResult[BlockSnapshot] {.requires:
    not services.preparing.} =
  ## Publish between dispatcher turns using the startup RPC choice; enabled-listener refusal never falls back.
  if services.chainRpc:
    services.canonical.applyAccumulation(services.rpc, source,
        limits) # Join all three handles before notifications.
  else:
    services.canonical.applyAccumulation(source, limits) # Disabled/default canonical owners still use existing guarded adoption.

func accumulationStage*(services: Services): AccumulationHandoffStage =
  ## Observe producer backpressure independently of optional listener lifetime.
  services.adoption.stage

proc enqueueAccumulation*(services: var Services, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): AccumulationEnqueueError {.requires:
    not services.preparing.} =
  ## Hand one finalized candidate to the next dispatcher turn; canonical authority is rechecked at adoption.
  services.adoption.enqueue(services.canonical, source, limits)

proc enqueueCandidate*(services: var Services, candidate: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: ApplicationCandidateLimits,
    composition: AccumulationCompositionLimits): ApplicationCandidateResult {.requires:
    not services.preparing.} =
  ## Prepare from this selected head and queue the genuine successor; publication waits for the next service tick.
  services.adoption.enqueueCandidate(services.canonical, candidate, ancestors, limits, composition)

proc beginBlockInput*(services: Services, input: var BlockInput, extent: ByteLimit,
    ancestors: openArray[OwnedHeader], resources: BlockInputLimits,
    policies: ApplicationCandidateLimits): BlockInputAdmission {.requires:
    not services.preparing.} =
  ## Bind bounded reception to this exact canonical history without preparing or publishing a block.
  input.begin(services.canonical, extent, ancestors, resources, policies)

proc enqueueBlockInput*(services: var Services, input: var BlockInput, id: BlockInputId,
    composition: AccumulationCompositionLimits): BlockInputResult {.requires:
    not services.preparing.} =
  ## Explicit producer work runs outside transport callbacks; finalized success waits for a later adoption tick.
  input.enqueue(id, services.canonical, services.adoption, composition)

func preparationActive*(services: Services): bool =
  ## Done and cancelled work still retain the canonical exclusion gate until collection or joined close.
  services.preparing

proc preparationAvailable*(services: Services): bool =
  ## Preflight scalar exclusion before reading any canonical handle; no implicit legacy state is permitted.
  if not services.started or services.preparing or services.rpc.chainPaused or
      services.adoption.stage != AccumulationHandoffStage.Idle:
    return false # Existing work/suspension forbids a new graph lease.
  services.canonical.stateSnapshot.error == StateStoreError.None

proc beginPreparation*(services: var Services, input: var BlockInput,
    id: BlockInputId): PreparationAdmission {.raises, requires: services.preparationAvailable.} =
  ## Pause RPC before worker admission; all existing external graph aliases must also remain untouched until collection/join.
  discard services.worker.start() # Reuse an existing idle thread without spawning per job.
  services.rpcLease = services.rpc.pauseChain()
  let admitted = services.worker.submit(input, id, services.canonical)
  if admitted.error == PreparationError.None:
    services.preparing = true # No fallible canonical/alias work follows successful worker submission.
  else:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # A refused input grants no lease and restores ordinary RPC ticks.
  admitted

proc preparationPhase*(services: var Services): PreparationPhase =
  ## Poll only the worker's synchronized scalar lifecycle state.
  services.worker.phase

proc cancelPreparation*(services: var Services, ticket: PreparationTicket): bool =
  ## Cancellation never reopens canonical or RPC access before actual retirement.
  services.worker.cancel(ticket)

proc collectPreparation*(services: var Services, ticket: PreparationTicket): PreparationCompletion =
  ## Move/drop completion only after execution temporaries retire, then restore canonical and RPC access together.
  result = services.worker.collect(ticket)
  if result.kind != PreparationCompletionKind.Uninitialized:
    services.preparing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Stale/early collection cannot release another active lease.

proc takeAccumulation*(services: var Services): ApplicationChainResult[BlockSnapshot] {.requires:
    services.accumulationStage == AccumulationHandoffStage.Finished.} =
  ## Acknowledge the exact retained outcome before accepting another candidate.
  services.adoption.take()

proc cancelAccumulation*(services: var Services): bool =
  ## Cancel only unattempted work; finished outcomes still require acknowledgement or explicit shutdown.
  if services.preparing: return false # Active preparation has no pending adoption to cancel.
  services.adoption.cancel()

proc tick*(services: var Services, peers: uint32) =
  ## Attempt one pending adoption between native callbacks; exclusive preparation leaves independent UI work available.
  if services.preparing:
    services.ui.tick()
    return # Never create RPC contexts or canonical ARC aliases while the worker owns its lease.
  if services.chainRpc:
    services.adoption.process(services.canonical, services.rpc) # Enabled listener failure remains a completed refusal.
  else:
    services.adoption.process(services.canonical) # No listener is needed for explicit independent adoption.
  services.rpc.tick(peers)
  services.ui.tick()

proc configureTelemetry*(services: var Services, options: Options, certificate: string,
    port: uint16, ipv6: bool): bool {.raises.} =
  ## Register the actual transport identity/address after binding, using the captured chain bytes.
  setupTelemetry(services.telemetry, options, certificate, port, ipv6, services.chainText)

proc stageCheckpointVerification*(services: var Services, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Independent fixed trust and explicit decode budgets require no canonical alias, so verification may run during preparation leases.
  services.checkpointExport.stageVerification(expected, limits, limit)
