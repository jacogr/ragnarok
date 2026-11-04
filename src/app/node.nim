# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable application node host manages inbound replies and bounded checked outbound reads through exact Services leases.
## Close this host before retiring Services storage; peer claims never select local finality.
import std/[monotimes, times]
import ./services
import ./proof/worker
import ../jamnp-s/[node as node_streams, connections, read_stream, read_client, read_validation,
    report_cache, admission]
import ../chain/[provider, genesis]
import ../codec/state/[safrole, consensus]
import ../codec/bounded

type
  CheckedRequestIdentity = ref object ## Host-only retained namespace prevents stale tickets matching a reopened or foreign host.
    marker: uint8
  CheckedRequestTicket* = object ## The namespace and nonwrapping serial bind acquisition and verification to one host operation.
    owner: nil CheckedRequestIdentity
    serial: uint64
  CheckedRequestStart* = object ## Admission failures grant no network or worker collection authority.
    case status: NodeError
    of None: ticket: CheckedRequestTicket
    else: discard # Default/refused admission contains only its reason.
  CheckedRequestPhase* {.pure.} = enum ## A complete network reply can wait for a foreign canonical worker without exposing bytes.
    Idle, Receiving, Waiting, Verifying, Done
  CheckedCompletionKind* {.pure.} = enum ## Only Completed exposes a whole verification result, whose own failure tag remains guarded.
    Uninitialized, Pending, Completed, Cancelled, TimedOut, Interrupted, NetworkFailure,
    AdmissionFailure
  CheckedRequestCompletion* = object ## No cancellation, transport or admission failure carries a checked response prefix.
    case status: CheckedCompletionKind
    of Completed: response: ReadVerificationResult[CheckedReadReply]
    of NetworkFailure: networkReason: ReadError
    of AdmissionFailure: admissionReason: ReadVerificationError
    else: discard # Pending/default/lifecycle failures have no payload.
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
    checkedIdentity: nil CheckedRequestIdentity
    checkedNext: uint64
    checkedPhase: CheckedRequestPhase
    checkedNetwork: NodeRequestTicket
    checkedWorker: ProofWorkerTicket
    checkedRequest: ReadRequest
    checkedLimits: ReadVerificationLimits
    checkedWire: seq[byte]
    checkedOutcome: CheckedRequestCompletion
    checkedCancel: CheckedCompletionKind
    checkedStarted: MonoTime
    preferChecked: bool
    reports: ReportCache
proc `=copy`*(destination: var ApplicationNode, source: ApplicationNode) {.error.}
  ## Copying the host would duplicate a worker ticket and move nested native callback addresses.
proc `=dup`*(source: ApplicationNode): ApplicationNode {.error.}
  ## Initialization cannot create another owner of the same borrowed Services/native lifetime.
proc `=wasMoved`*(owner: var ApplicationNode) {.nodestroy, requires: not owner.opened.} =
  ## Only explicit joined/retired hosts may move their child storage.
  `=wasMoved`(owner.streams)
  `=wasMoved`(owner.workerTicket)
  `=wasMoved`(owner.checkedIdentity)
  `=wasMoved`(owner.checkedWorker)
  `=wasMoved`(owner.checkedWire)
  `=wasMoved`(owner.checkedOutcome)
  `=wasMoved`(owner.reports)
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
  `=destroy`(owner.checkedIdentity)
  `=destroy`(owner.checkedWorker)
  `=destroy`(owner.checkedWire)
  `=destroy`(owner.checkedOutcome)
  `=destroy`(owner.reports)
func isOpen*(owner: ApplicationNode): bool =
  ## Default and explicitly closed hosts grant no peer/read authority.
  owner.opened
func cachedReportCount*(owner: ApplicationNode): int =
  ## Detached cache statistics are safe while any canonical worker owns the graph.
  owner.reports.len
func cachedReportBytes*(owner: ApplicationNode): int =
  ## Logical immutable cache wire bytes exclude native buffers and transient response copies.
  owner.reports.byteLength
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
func error*(started: CheckedRequestStart): NodeError =
  ## Observe admission without granting a ticket from a failed/default start.
  started.status
func value*(started: CheckedRequestStart): CheckedRequestTicket {.requires: started.status ==
    NodeError.None.} =
  ## Only accepted bounded network acquisition grants the exact host generation.
  started.ticket
func kind*(completed: CheckedRequestCompletion): CheckedCompletionKind =
  ## Observe lifecycle failure without extracting any accepted body.
  completed.status
func value*(completed: CheckedRequestCompletion): ReadVerificationResult[
    CheckedReadReply] {.requires: completed.status == CheckedCompletionKind.Completed.} =
  ## The inner verifier still distinguishes complete checked success from semantic/proof failure.
  completed.response
func networkError*(completed: CheckedRequestCompletion): ReadError {.requires: completed.status ==
    CheckedCompletionKind.NetworkFailure.} =
  ## Transport failure reasons are carried only by an actual failed collection.
  completed.networkReason
func admissionError*(completed: CheckedRequestCompletion): ReadVerificationError {.requires: completed.status ==
    CheckedCompletionKind.AdmissionFailure.} =
  ## Trusted-source capture refusals remain distinct from later cryptographic failures.
  completed.admissionReason
func checkedLive*(owner: ApplicationNode, ticket: CheckedRequestTicket): bool =
  ## Complete uncollected operations occupy capacity; default, foreign, stale and reopened tickets cannot match.
  owner.opened and owner.checkedPhase != CheckedRequestPhase.Idle and ticket.owner != nil and
    ticket.owner == owner.checkedIdentity and ticket.serial == owner.checkedNext
func checkedPhase*(owner: ApplicationNode, ticket: CheckedRequestTicket): CheckedRequestPhase =
  ## Phase is scalar and may be observed while a foreign worker owns canonical ARC graphs.
  if owner.checkedLive(ticket): owner.checkedPhase else: CheckedRequestPhase.Idle
proc clearChecked(owner: var ApplicationNode) =
  ## Retire detached buffers and exact tickets only after matching worker collection/join or before admission.
  owner.checkedPhase = CheckedRequestPhase.Idle
  owner.checkedNetwork = default(NodeRequestTicket)
  owner.checkedWorker = default(ProofWorkerTicket)
  owner.checkedRequest = default(ReadRequest)
  owner.checkedLimits = default(ReadVerificationLimits)
  owner.checkedWire = @[]
  owner.checkedOutcome = default(CheckedRequestCompletion)
  owner.checkedCancel = CheckedCompletionKind.Uninitialized
  owner.checkedStarted = default(MonoTime)
proc requestChecked*(owner: var ApplicationNode, peer: NodePeer, request: ReadRequest,
    limits: ReadVerificationLimits): CheckedRequestStart =
  ## Reserve one complete acquisition-to-verification operation; native framing applies the same hard byte ceiling.
  if not owner.opened: return CheckedRequestStart(status: NodeError.Unavailable)
  if owner.checkedPhase != CheckedRequestPhase.Idle: return CheckedRequestStart(
      status: NodeError.Unavailable)
  if not request.valid: return CheckedRequestStart(status: NodeError.InvalidConfig)
  let minimum = if request.kind == ReadKind.State: 8'u64 else: 4'u64
  if uint64(limits.wireBytes) < minimum or uint64(limits.wireBytes) > uint64(MaxReadReplyBytes):
    return CheckedRequestStart(status: NodeError.InvalidConfig)
  if owner.checkedNext == high(uint64): return CheckedRequestStart(status: NodeError.Exhausted)
  let admitted = owner.streams.request(peer, request, limits.wireBytes)
  if admitted.error != NodeError.None: return CheckedRequestStart(status: admitted.error)
  inc owner.checkedNext
  owner.checkedNetwork = admitted.value
  owner.checkedRequest = request
  owner.checkedLimits = limits
  owner.checkedStarted = getMonoTime()
  owner.checkedPhase = CheckedRequestPhase.Receiving
  CheckedRequestStart(status: NodeError.None, ticket: CheckedRequestTicket(
    owner: owner.checkedIdentity, serial: owner.checkedNext))
proc cancelChecked(owner: var ApplicationNode, reason: CheckedCompletionKind) =
  ## Admitted CPU work keeps its exact lease until collection, even when cancellation follows Done.
  if owner.checkedPhase == CheckedRequestPhase.Verifying:
    if owner.checkedCancel == CheckedCompletionKind.Uninitialized:
      owner.checkedCancel = reason
      let services = owner.services
      if services != nil: discard services[].cancelStateProof(owner.checkedWorker)
  else:
    if owner.checkedPhase == CheckedRequestPhase.Receiving:
      discard owner.streams.cancelRequest(owner.checkedNetwork)
    owner.checkedWire = @[]
    owner.checkedOutcome = CheckedRequestCompletion(status: reason)
    owner.checkedPhase = CheckedRequestPhase.Done
proc cancelChecked*(owner: var ApplicationNode, ticket: CheckedRequestTicket): bool =
  ## Cancellation is scoped to this checked operation and never joins/cancels a foreign Services job.
  if not owner.checkedLive(ticket): return false
  owner.cancelChecked(CheckedCompletionKind.Cancelled)
  true
proc takeChecked*(owner: var ApplicationNode, ticket: CheckedRequestTicket): CheckedRequestCompletion =
  ## A pending result grants no body and cannot retire an admitted lease; one terminal collection frees capacity.
  if not owner.checkedLive(ticket): return default(CheckedRequestCompletion)
  if owner.checkedPhase != CheckedRequestPhase.Done:
    return CheckedRequestCompletion(status: CheckedCompletionKind.Pending)
  result = move(owner.checkedOutcome)
  owner.clearChecked()
proc receiveChecked(owner: var ApplicationNode, clock: MonoTime) =
  ## Bound detached waiting time even while an unrelated Services job holds the graph gate.
  if owner.checkedPhase in [CheckedRequestPhase.Receiving, CheckedRequestPhase.Waiting,
      CheckedRequestPhase.Verifying]:
    if clock < owner.checkedStarted or (clock-owner.checkedStarted).inMilliseconds >= 120000:
      owner.cancelChecked(CheckedCompletionKind.TimedOut)
  if owner.checkedPhase != CheckedRequestPhase.Receiving: return
  let completed = owner.streams.takeReply(owner.checkedNetwork)
  if completed.error == ReadError.Unavailable: return # Exact FIN has not arrived; retain native input accounting and ticket.
  if completed.error != ReadError.None:
    discard owner.streams.cancelRequest(owner.checkedNetwork)
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.NetworkFailure,
      networkReason: completed.error)
    owner.checkedPhase = CheckedRequestPhase.Done
    return
  owner.checkedWire = completed.value.bytes # Fresh detached bounded bytes outlive real native stream retirement.
  owner.checkedNetwork = default(NodeRequestTicket)
  owner.checkedPhase = CheckedRequestPhase.Waiting
proc collectChecked(owner: var ApplicationNode) =
  ## Collect only this exact CPU generation; a foreign Done operation cannot be retired by this ticket.
  if owner.checkedPhase != CheckedRequestPhase.Verifying: return
  let services = owner.services
  if services == nil: return
  let phase = services[].stateProofPhase
  if phase in [ProofWorkerPhase.Queued, ProofWorkerPhase.Running]: return
  let completed = services[].collectStateProof(owner.checkedWorker)
  if owner.checkedCancel != CheckedCompletionKind.Uninitialized:
    owner.checkedOutcome = CheckedRequestCompletion(status: owner.checkedCancel)
  elif completed.kind == ProofWorkerCompletionKind.ReadVerified:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.Completed,
      response: completed.verifiedReadValue)
    let checked = completed.verifiedReadValue
    if checked.error == ReadVerificationError.None and checked.value.kind == ReadKind.Report:
      discard owner.reports.remember(checked.value) # Local retention refusal cannot turn a complete checked read into failed delivery.
  else:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.Interrupted)
  owner.checkedWorker = default(ProofWorkerTicket)
  owner.checkedPhase = CheckedRequestPhase.Done
proc submitChecked(owner: var ApplicationNode): bool {.raises.} =
  ## Admit after temporary trusted-source capture retires; Busy leaves one bounded detached reply waiting.
  if owner.checkedPhase != CheckedRequestPhase.Waiting: return false
  let services = owner.services
  if services == nil: return false
  let admitted = services[].beginReadVerification(owner.checkedRequest, owner.checkedWire,
    owner.checkedLimits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  owner.checkedWire = @[]
  if admitted.error == StateProofAdmissionError.None:
    owner.checkedWorker = admitted.value
    owner.checkedPhase = CheckedRequestPhase.Verifying
  elif admitted.error == StateProofAdmissionError.QueryFailure:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.AdmissionFailure,
      admissionReason: admitted.verificationError)
    owner.checkedPhase = CheckedRequestPhase.Done
  else:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.Interrupted)
    owner.checkedPhase = CheckedRequestPhase.Done
  owner.preferChecked = false # An inbound responder gets first opportunity after this verification turn.
  true
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
  owner.clearChecked()
  owner.checkedIdentity = CheckedRequestIdentity(marker: 1)
  owner.checkedNext = 0
  owner.preferChecked = false
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
  if owner.checkedPhase == CheckedRequestPhase.Verifying and services != nil:
    if services[].cancelStateProof(owner.checkedWorker):
      services[].stopStateProofs() # Joined teardown belongs only to a successfully matched checked-request ticket.
  owner.streams.close()
  owner.clearChecked()
  owner.reports.clear()
  owner.checkedIdentity = nil
  owner.clearJob()
  owner.opened = false
  owner.epochHeld = false
  owner.services = nil
  owner.stamp = default(SourceStamp)
proc serveCached(owner: var ApplicationNode, task: NodeReadTask): bool =
  ## A hit needs no canonical graph or worker, but still requires the native ticket's exact method/hash binding.
  if task.request.kind != ReadKind.Report: return false
  let found = owner.reports.find(task.request)
  if found.error != ReportCacheError.None: return false
  if owner.streams.respond(task.ticket, found.value) != ReadError.None:
    discard owner.streams.reject(task.ticket) # Output pressure cannot orphan an already claimed cached request.
  owner.preferChecked = true
  true
proc serveDetached(owner: var ApplicationNode) =
  ## Inspect at most one report while a foreign graph is frozen; cache misses return their claim without resetting deadlines.
  if owner.reports.len == 0: return
  let task = owner.streams.takeRead(ReadKind.Report)
  if task.error != NodeError.None: return
  if owner.serveCached(task.value): return
  if not owner.streams.deferRead(task.value.ticket):
    discard owner.streams.reject(task.value.ticket) # Failed revocation never leaves taken work without an owner.
proc poll*(owner: var ApplicationNode, clock: MonoTime, now: StateTime,
    maximumMs: range[0..1] = 1): bool {.raises.} =
  ## Service detached native data during CPU work; capture/refresh only after the exclusive graph gate opens.
  if not owner.opened or owner.services == nil: return false
  if not owner.streams.poll(clock, maximumMs): return false
  let services = owner.services
  if services == nil: return false
  owner.receiveChecked(clock)
  owner.collectChecked()
  if not services[].stateProofAvailable: owner.serveDetached()
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
  if owner.preferChecked and owner.submitChecked(): return true
  let request = owner.streams.takeRead()
  if request.error != NodeError.None:
    discard owner.submitChecked()
    return true
  if owner.serveCached(request.value): return true
  let admitted = services[].beginNetworkRead(request.value.request)
  if admitted.error != StateProofAdmissionError.None:
    discard owner.streams.reject(request.value.ticket)
    return true # Busy/missing data resets the request instead of fabricating an empty successful answer.
  owner.workerTicket = admitted.value
  owner.readTicket = request.value.ticket
  owner.preferChecked = true # Ready inbound and checked outbound work alternate instead of competing by physical stream order.
  owner.pending = true
  owner.cancelled = false
  true
