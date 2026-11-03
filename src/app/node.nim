# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable application node host borrows Services and manages one exact canonical read lease.
## Close this host before retiring Services storage; peer claims never select local finality.
import std/monotimes
import ./services
import ./proof/worker
import ../jamnp-s/[node as node_streams, connections, read_stream, read_client, admission]
import ../chain/[provider, genesis]
import ../codec/state/[safrole, consensus]
import ../codec/bounded

type
  SourceStamp = object ## Fixed local source facts survive exclusive worker access without ARC aliases.
    head, finalized: array[32, byte]
    now: StateTime
  ApplicationNode* = object ## Noncopyable host/native ownership borrows one stable Services address through explicit close.
    opened, pending, cancelled, epochHeld: bool
    services: nil ptr Services
    streams: NodeService
    workerTicket: ProofWorkerTicket
    readTicket: NodeReadTicket
    stamp: SourceStamp
proc `=copy`*(destination: var ApplicationNode, source: ApplicationNode) {.error.}
  ## Copying the host would duplicate a worker ticket and move nested native callback addresses.
proc `=dup`*(source: ApplicationNode): ApplicationNode {.error.}
  ## Initialization cannot create another owner of the same borrowed Services/native lifetime.
proc `=wasMoved`*(owner: var ApplicationNode) {.nodestroy, requires: not owner.opened.} =
  ## Only explicit joined/retired hosts may move their child storage.
  `=wasMoved`(owner.streams)
  `=wasMoved`(owner.workerTicket)
  owner.opened = false
  owner.pending = false
  owner.cancelled = false
  owner.epochHeld = false
  owner.services = nil
  owner.readTicket = default(NodeReadTicket)
  owner.stamp = default(SourceStamp)
proc requireClosed(owner: ApplicationNode) {.requires: not owner.opened.} =
  ## Native contexts and borrowed Services storage must be retired before destruction.
  discard
proc `=destroy`*(owner: ApplicationNode) =
  ## Destruction neither abandons an active CPU lease nor silently joins unrelated Services work.
  requireClosed(owner)
  `=destroy`(owner.streams)
  `=destroy`(owner.workerTicket)
func isOpen*(owner: ApplicationNode): bool =
  ## Default and explicitly closed hosts grant no peer/read authority.
  owner.opened
proc localPort*(owner: ApplicationNode): uint16 =
  ## Observe detached native listener state without a canonical graph alias.
  if owner.opened: owner.streams.localPort else: 0'u16
proc peerCount*(owner: ApplicationNode): int =
  ## Expose authenticated logical reservations for ordinary service diagnostics.
  if owner.opened: owner.streams.peerCount else: 0
proc peerAt*(owner: ApplicationNode, ordinal: int): NodeResult[NodePeer] =
  ## The nested actor's generation token still requires live-source checks.
  owner.streams.peerAt(ordinal)
proc source*(owner: ApplicationNode, peer: NodePeer): NodeResult[NodeClaims] =
  ## Detached remote claims carry no canonical adoption or finality authority.
  owner.streams.source(peer)
proc request*(owner: var ApplicationNode, peer: NodePeer, request: ReadRequest,
    maximum = ByteLimit(MaxReadReplyBytes)): NodeResult[NodeRequestTicket] =
  ## Fixed outbound request facts may be queued while a Services worker owns the unrelated canonical graph.
  owner.streams.request(peer, request, maximum)
proc takeReply*(owner: var ApplicationNode, ticket: NodeRequestTicket): ReadClientResult =
  ## Complete detached bytes remain untrusted; the host must acquire any state/proof validation gate separately.
  owner.streams.takeReply(ticket)
proc cancelRequest*(owner: var ApplicationNode, ticket: NodeRequestTicket): bool =
  ## Cancelling an outbound network stream never cancels a Services canonical worker lease.
  owner.streams.cancelRequest(ticket)
proc requestLive*(owner: ApplicationNode, ticket: NodeRequestTicket): bool =
  ## Exact peer generation and serial bind outbound activity independently of canonical CPU ownership.
  owner.streams.requestLive(ticket)
proc stage(owner: var ApplicationNode, config: ConnectionConfig, limits: SafroleStateConfig,
    now: StateTime): NodeError =
  ## Every temporary Services view retires on return, before the host can submit native CPU work.
  let services = owner.services
  if services == nil: return NodeError.Unavailable
  let view = services[].chainView
  let head = view.bestBlock
  let finalized = view.finalizedBlock
  if head.error != GenesisError.None: return NodeError.InvalidSource
  if finalized.error != GenesisError.None: return NodeError.NoFinality
  if head.value.slot > uint64(uint32(now)): return NodeError.InvalidSource
  let opened = owner.streams.open(config, view, limits)
  if opened != NodeError.None: return opened
  owner.stamp = SourceStamp(head: array[32, byte](head.value.blockHash),
    finalized: array[32, byte](finalized.value.blockHash), now: now)
  NodeError.None
proc open*(owner: var ApplicationNode, services: var Services, config: ConnectionConfig,
    limits: SafroleStateConfig, now: StateTime): NodeError =
  ## Bind exactly one stable full-state Services owner; missing finality never falls back to best.
  if owner.opened or config.protocol.len == 0 or config.protocol != services.nodeProtocol:
    return NodeError.InvalidConfig # Full-state networking uses the original configured genesis, never a mutable best head.
  if not services.stateProofAvailable: return NodeError.Unavailable
  owner.services = addr services
  let opened = owner.stage(config, limits, now)
  if opened != NodeError.None:
    owner.streams.close()
    owner.services = nil
    return opened # Failed factories retain neither a Services borrow nor native callbacks.
  owner.epochHeld = false
  owner.opened = true
  NodeError.None
proc refresh(owner: var ApplicationNode, now: StateTime): NodeError =
  ## Capture changed source metadata only under the graph gate, without retaining any map/header owner.
  let services = owner.services
  if services == nil: return NodeError.Unavailable
  let view = services[].chainView
  let head = view.bestBlock
  let finalized = view.finalizedBlock
  if head.error != GenesisError.None: return NodeError.InvalidSource
  if finalized.error != GenesisError.None: return NodeError.NoFinality
  if uint32(now) < uint32(owner.stamp.now) or head.value.slot > uint64(uint32(now)):
    return NodeError.InvalidSource # Epoch transition delay uses explicit local JAM time, never remote slots.
  let headHash = array[32, byte](head.value.blockHash)
  let finalizedHash = array[32, byte](finalized.value.blockHash)
  if headHash == owner.stamp.head and finalizedHash == owner.stamp.finalized:
    if not owner.epochHeld or uint32(now) == uint32(owner.stamp.now):
      owner.stamp.now = now
      return NodeError.None # Clock ticks alone cannot broadcast the unchanged header; retry only a held epoch gate.
  let advanced = owner.streams.advance(view, now)
  if advanced.error != NodeError.None: return advanced.error
  owner.epochHeld = advanced.value == EpochUpdate.Held
  owner.stamp = SourceStamp(head: headHash, finalized: finalizedHash, now: now)
  NodeError.None
proc clearJob(owner: var ApplicationNode) =
  ## Drop host-only tickets only after matching collection/join or confirmed stale retirement.
  owner.pending = false
  owner.cancelled = false
  owner.workerTicket = default(ProofWorkerTicket)
  owner.readTicket = default(NodeReadTicket)
proc close*(owner: var ApplicationNode) =
  ## Cancel/join only this host's exact worker before retiring native callbacks and the Services borrow.
  owner.streams.stop()
  let services = owner.services
  if owner.pending and services != nil:
    if services[].cancelStateProof(owner.workerTicket):
      services[].stopStateProofs() # Successful exact-ticket cancellation proves this serialized host owns the joined job.
  owner.streams.close()
  owner.clearJob()
  owner.opened = false
  owner.epochHeld = false
  owner.services = nil
  owner.stamp = default(SourceStamp)
proc poll*(owner: var ApplicationNode, clock: MonoTime, now: StateTime,
    maximumMs: range[0..1] = 1): bool {.raises.} =
  ## Service detached native data during CPU work; capture/refresh only after the exclusive graph gate opens.
  if not owner.opened or owner.services == nil: return false
  if not owner.streams.poll(clock, maximumMs): return false
  let services = owner.services
  if services == nil: return false
  if owner.pending:
    if not owner.cancelled and not owner.streams.readLive(owner.readTicket):
      owner.cancelled = services[].cancelStateProof(owner.workerTicket)
    let phase = services[].stateProofPhase
    if phase in [ProofWorkerPhase.Queued, ProofWorkerPhase.Running]: return true
    if phase == ProofWorkerPhase.Done:
      let completed = services[].collectStateProof(owner.workerTicket)
      if completed.kind == ProofWorkerCompletionKind.ReadCompleted and
          completed.readValue.error == ReadError.None and owner.streams.readLive(owner.readTicket):
        if owner.streams.respond(owner.readTicket, completed.readValue.value) != ReadError.None:
          discard owner.streams.reject(owner.readTicket) # Bounded output pressure cannot orphan an already taken task.
      else:
        discard owner.streams.reject(owner.readTicket) # Cancellation/stale collection never emits a successful response prefix.
    else:
      discard owner.streams.reject(owner.readTicket) # External joined Services shutdown has already retired the old worker.
    owner.clearJob()
  if not services[].stateProofAvailable: return true # Foreign RPC/preparation/publication leases remain untouched.
  if owner.refresh(now) != NodeError.None: return false
  let request = owner.streams.takeRead()
  if request.error != NodeError.None: return true
  let admitted = services[].beginNetworkRead(request.value.request)
  if admitted.error != StateProofAdmissionError.None:
    discard owner.streams.reject(request.value.ticket)
    return true # Busy/missing data resets the request instead of fabricating an empty successful answer.
  owner.workerTicket = admitted.value
  owner.readTicket = request.value.ticket
  owner.pending = true
  owner.cancelled = false
  true
