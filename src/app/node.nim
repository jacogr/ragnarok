# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable application node host manages inbound replies and bounded checked outbound reads through exact Services leases.
## Close this host before retiring Services storage; peer claims never select local finality.
import std/[monotimes, times]
import ./services
import ./preimage_followup
import ./proof/worker
import ../jamnp-s/[node as node_streams, connections, read_stream, read_client, read_validation,
    report_cache, preimage_cache, preimage_announcement, preimage_gossip, admission,
    ticket_packet, ticket_validation, ticket_pool, ticket_forwarding]
import ../chain/[provider, genesis]
import ../codec/state/[safrole, consensus, service_values, requests]
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
    pendingRequest: ReadRequest
    stamp: SourceStamp
    checkedIdentity: nil CheckedRequestIdentity
    checkedNext: uint64
    checkedPhase: CheckedRequestPhase
    checkedNetwork: NodeRequestTicket
    checkedPeer: NodePeer
    checkedWorker: ProofWorkerTicket
    checkedRequest: ReadRequest
    checkedLimits: ReadVerificationLimits
    checkedWire: seq[byte]
    checkedOutcome: CheckedRequestCompletion
    checkedCancel: CheckedCompletionKind
    checkedStarted: MonoTime
    preferChecked, preferFetch, preferPreimage: bool
    preimages: PreimageFollowups
    gossip: PreimageGossip
    reports: ReportCache
    tickets: PendingTicketPool
    forwarding: TicketForwarding
    connectivityApplied: StateTime
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
  `=wasMoved`(owner.tickets)
  `=wasMoved`(owner.forwarding)
  `=wasMoved`(owner.preimages)
  `=wasMoved`(owner.gossip)
  `=wasMoved`(owner.checkedPeer)
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
  `=destroy`(owner.tickets)
  `=destroy`(owner.forwarding)
  `=destroy`(owner.preimages)
  `=destroy`(owner.gossip)
  `=destroy`(owner.checkedPeer)
func isOpen*(owner: ApplicationNode): bool =
  ## Default and explicitly closed hosts grant no peer/read authority.
  owner.opened
func ticketForwardingCount*(owner: ApplicationNode): int =
  ## Observe retained proxy intents without borrowing canonical state.
  owner.forwarding.len
func ticketForwardingActive*(owner: ApplicationNode): int =
  ## Exact native requests remain separately bounded within the shared read quota.
  owner.forwarding.sending
func forwardedTickets*(owner: ApplicationNode): uint64 =
  ## Count complete transport acknowledgments without claiming canonical inclusion.
  owner.forwarding.acknowledged
func cachedReportCount*(owner: ApplicationNode): int =
  ## Detached cache statistics are safe while any canonical worker owns the graph.
  owner.reports.len
func cachedReportBytes*(owner: ApplicationNode): int =
  ## Logical immutable cache wire bytes exclude native buffers and transient response copies.
  owner.reports.byteLength
func cachedPreimageCount*(owner: ApplicationNode): int =
  ## Observe detached hash-checked blob count independently of canonical graph leases.
  owner.preimages.cachedCount
func cachedPreimageBytes*(owner: ApplicationNode): int =
  ## Logical framed cache usage includes the four-byte CE143 prefix.
  owner.preimages.cachedBytes
func pendingPreimageCount*(owner: ApplicationNode): int =
  ## Queued and active automatic retrievals have a separate fixed eight-intent capacity.
  owner.preimages.pendingCount
func preimageGossipCount*(owner: ApplicationNode): int =
  ## Fixed detached possession intents do not imply inclusion or remote adoption.
  owner.gossip.len
func preimageGossipSending*(owner: ApplicationNode): bool =
  ## Observe detached native announcement ownership without reading canonical state.
  owner.gossip.sending
func deliveredPreimageGossip*(owner: ApplicationNode): uint64 =
  ## Count successful exact bare-FIN deliveries, independently of content/state authority.
  owner.gossip.deliveredCount
func pendingTicketCount*(owner: ApplicationNode): int =
  ## Detached prospective GP ticket count grants no canonical inclusion authority.
  owner.tickets.len
proc pendingTicketAt*(owner: ApplicationNode, ordinal: int): CheckedNetworkTicket {.requires: ordinal >=
    0 and ordinal < owner.tickets.len.} =
  ## Only complete sealed proof metadata leaves retention; no mutable pool row or worker ticket escapes.
  owner.tickets.ticketAt(ordinal)
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
  owner.checkedPeer = default(NodePeer)
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
  let minimum = request.minimumReplyBytes
  if uint64(limits.wireBytes) < minimum or uint64(limits.wireBytes) > uint64(MaxReadReplyBytes):
    return CheckedRequestStart(status: NodeError.InvalidConfig)
  if owner.checkedNext == high(uint64): return CheckedRequestStart(status: NodeError.Exhausted)
  let admitted = owner.streams.request(peer, request, limits.wireBytes)
  if admitted.error != NodeError.None: return CheckedRequestStart(status: admitted.error)
  inc owner.checkedNext
  owner.checkedNetwork = admitted.value
  owner.checkedPeer = peer
  owner.checkedRequest = request
  owner.checkedLimits = limits
  owner.checkedStarted = getMonoTime()
  owner.checkedPhase = CheckedRequestPhase.Receiving
  CheckedRequestStart(status: NodeError.None, ticket: CheckedRequestTicket(
    owner: owner.checkedIdentity, serial: owner.checkedNext))
proc announcePreimage*(owner: var ApplicationNode, peer: NodePeer, service: ServiceIndex,
    blob: CheckedReadReply, limits: ReadVerificationLimits): CheckedRequestStart =
  ## Publish only retained full-hash content requested in local canonical state, to an authenticated validator recipient.
  if not owner.opened or owner.services == nil: return CheckedRequestStart(
      status: NodeError.Unavailable)
  if not blob.valid or blob.kind != ReadKind.Preimage: return CheckedRequestStart(
      status: NodeError.InvalidConfig)
  if not owner.streams.isValidator(peer): return CheckedRequestStart(
      status: NodeError.InvalidSource)
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return CheckedRequestStart(
      status: NodeError.Unavailable)
  let notice = announcementRequest(service, blob.preimageHash, RequestLength(uint32(
      blob.preimageByteLength)))
  if notice.error != ReadError.None: return CheckedRequestStart(status: NodeError.InvalidConfig)
  if services[].chainView.requested(notice.value) != ReadError.None:
    return CheckedRequestStart(status: NodeError.InvalidSource) # This bounded account/history query retires before native admission.
  if owner.checkedPhase != CheckedRequestPhase.Idle: return CheckedRequestStart(
      status: NodeError.Unavailable)
  if owner.preimages.retain(blob) != PreimageCacheError.None:
    return CheckedRequestStart(status: NodeError.LimitExceeded)
  owner.requestChecked(peer, notice.value.request, limits)
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
    if checked.error == ReadVerificationError.None and checked.value.kind == ReadKind.Preimage:
      discard owner.preimages.retain(checked.value) # Public checked reads can populate detached content without canonical mutation.
    if checked.error == ReadVerificationError.None and checked.value.kind ==
        ReadKind.PreimageAnnouncement:
      let notice = decodeAnnouncement(checked.value.request.payload)
      if notice.error == ReadError.None and owner.preimages.has(notice.value):
        discard owner.gossip.offer(owner.streams, notice.value,
            owner.checkedPeer) # An already acknowledged publisher recipient needs no duplicate gossip.
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
  owner.preferFetch = true
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
  owner.connectivityApplied = now # Initial installation is the first actual connectivity application.
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
  owner.preimages.reset()
  owner.preferFetch = false
  owner.preferPreimage = false
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
  let previousEpoch = owner.streams.connectivityEpoch
  let advanced = owner.streams.advance(view, now)
  if advanced.error != NodeError.None: return advanced.error
  if owner.streams.connectivityEpoch != previousEpoch:
    owner.connectivityApplied = now # Same-epoch source updates never restart either ticket delay.
  owner.epochHeld = advanced.value == EpochUpdate.Held
  owner.stamp = SourceStamp(head: headHash, finalized: finalizedHash, now: now)
  NodeError.None
proc clearJob(owner: var ApplicationNode) =
  ## Drop host-only tickets only after matching collection/join or confirmed stale retirement.
  owner.pending = false
  owner.cancelled = false
  owner.workerTicket = default(ProofWorkerTicket)
  owner.readTicket = default(NodeReadTicket)
  owner.pendingRequest = default(ReadRequest)
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
  if services != nil: owner.preimages.close(services[], owner.streams)
  owner.gossip.close(owner.streams)
  owner.forwarding.close(owner.streams)
  owner.streams.close()
  owner.clearChecked()
  owner.reports.clear()
  owner.tickets.clear()
  owner.checkedIdentity = nil
  owner.clearJob()
  owner.opened = false
  owner.epochHeld = false
  owner.services = nil
  owner.stamp = default(SourceStamp)
proc serveCached(owner: var ApplicationNode, task: NodeReadTask): bool =
  ## A hit needs no canonical graph or worker, but still requires the native ticket's exact method/hash binding.
  case task.request.kind
  of ReadKind.Report:
    let found = owner.reports.find(task.request)
    if found.error != ReportCacheError.None: return false
    if owner.streams.respond(task.ticket, found.value) != ReadError.None:
      discard owner.streams.reject(task.ticket) # Output pressure cannot orphan a claimed cached request.
  of ReadKind.Preimage:
    let found = owner.preimages.find(task.request)
    if found.error != PreimageCacheError.None: return false
    if owner.streams.respond(task.ticket, found.value) != ReadError.None:
      discard owner.streams.reject(task.ticket) # Retained content has the same exact native ticket constraints.
  else: return false # Other methods require their canonical backend, never guessed cached state.
  owner.preferChecked = true
  true
proc serveDetached(owner: var ApplicationNode) =
  ## Inspect one cached kind per turn; alternate when both are populated and preserve original miss deadlines.
  if owner.reports.len == 0 and owner.preimages.cachedCount == 0: return
  let preimage = owner.preimages.cachedCount > 0 and (owner.reports.len == 0 or
      owner.preferPreimage)
  owner.preferPreimage = not preimage
  let selected = if preimage: ReadKind.Preimage else: ReadKind.Report
  let task = owner.streams.takeRead(selected)
  if task.error != NodeError.None: return
  if owner.serveCached(task.value): return
  if not owner.streams.deferRead(task.value.ticket):
    discard owner.streams.reject(task.value.ticket) # Failed revocation never leaves taken work without an owner.
proc dispatchGossip(owner: var ApplicationNode, clock: MonoTime) =
  ## Retire every temporary canonical request lookup in this activation before the host can admit its next CPU worker.
  let services = owner.services
  if services == nil: return
  let candidate = owner.gossip.candidate()
  if candidate.valid:
    let notice = candidate.notice
    if not owner.preimages.has(notice) or services[].chainView.requested(notice) != ReadError.None:
      discard owner.gossip.reject(owner.streams, candidate) # No canonical alias is retained across dispatch or worker admission.
    else:
      discard owner.gossip.dispatch(owner.streams, candidate,
          clock) # Accepted topology and live recipient generation are checked at the actual send.
proc refreshTickets(owner: var ApplicationNode, now: StateTime) =
  ## Source aliases retire here before another CPU job can borrow the shared ARC input context.
  if owner.tickets.len == 0: return
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return
  let selected = services[].currentTicketSource()
  if selected.error == NetworkTicketError.None:
    discard owner.tickets.advance(selected.value, now)
proc finishTicket(owner: var ApplicationNode,
    outcome: NetworkTicketResult[CheckedNetworkTicket], now: StateTime): bool =
  ## Completed proof work still needs fresh clock/context/stream eligibility before retention or acknowledgment.
  if outcome.error notin [NetworkTicketError.None, NetworkTicketError.AlreadyIncluded]: return false
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return false
  let source = services[].currentTicketSource()
  if source.error != NetworkTicketError.None: return false
  if not source.value.allowsTime(now, owner.streams.connectivityEpoch): return false
  if outcome.error == NetworkTicketError.AlreadyIncluded: return true # Genuine verified finalized inclusion needs no new pending owner.
  if owner.tickets.advance(source.value, now) != TicketPoolError.None: return false
  let retained = owner.tickets.retain(outcome.value, now)
  if retained == TicketPoolError.AlreadyIncluded: return true
  if retained notin [TicketPoolError.None, TicketPoolError.Duplicate]: return false
  if outcome.value.delivery == TicketDelivery.Proxy:
    if owner.forwarding.advance(owner.streams, source.value, now, owner.connectivityApplied):
      discard owner.forwarding.offer(outcome.value) # Admission after the forwarding window may still supply a valid pending block input.
  true
proc dispatchTickets(owner: var ApplicationNode, now: StateTime, clock: MonoTime) =
  ## Retire all selected-source aliases before another canonical worker can be submitted.
  if owner.forwarding.len == 0: return
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return
  let selected = services[].currentTicketSource()
  if selected.error != NetworkTicketError.None:
    owner.forwarding.close(owner.streams)
    return
  if owner.forwarding.advance(owner.streams, selected.value, now, owner.connectivityApplied):
    discard owner.forwarding.dispatch(owner.streams, now, clock)
proc beginIncoming(owner: var ApplicationNode, task: NodeReadTask,
    now: StateTime): bool {.raises.} =
  ## Each specialized admission retires staging aliases before its one exact worker can execute.
  let services = owner.services
  if services == nil: return false
  if task.request.kind in [ReadKind.TicketProxy, ReadKind.TicketDistribution]:
    let peer = task.ticket.sourcePeer
    if not owner.streams.isValidator or not owner.streams.isValidator(peer): return false
    let packet = decodeTicketPacket(task.request.payload)
    if packet.error != TicketPacketError.None: return false
    let delivery = if task.request.kind == ReadKind.TicketProxy: TicketDelivery.Proxy else: TicketDelivery.Distribution
    let recipient = TicketRecipient(local: owner.streams.localIdentity, peer: peer.identity,
        now: now, connectivityEpoch: owner.streams.connectivityEpoch, delivery: delivery)
    let admitted = services[].beginNetworkTicket(packet.value, recipient)
    if admitted.error != StateProofAdmissionError.None: return false
    owner.workerTicket = admitted.value
  else:
    let admitted = services[].beginNetworkRead(task.request)
    if admitted.error != StateProofAdmissionError.None: return false
    owner.workerTicket = admitted.value
  owner.readTicket = task.ticket
  owner.pendingRequest = task.request
  owner.preferFetch = true
  owner.preferChecked = true # Inbound semantic admission keeps existing arbitration with public checked reads and private content fetches.
  owner.pending = true
  owner.cancelled = false
  true
proc poll*(owner: var ApplicationNode, clock: MonoTime, now: StateTime,
    maximumMs: range[0..1] = 1): bool {.raises.} =
  ## Service detached native data during CPU work; capture/refresh only after the exclusive graph gate opens.
  if not owner.opened or owner.services == nil: return false
  if not owner.streams.poll(clock, maximumMs): return false
  let services = owner.services
  if services == nil: return false
  owner.tickets.expire(now) # Host-only proof owners may retire while a different job holds immutable source/context aliases.
  owner.forwarding.expire(owner.streams, now)
  owner.forwarding.poll(owner.streams, clock)
  owner.gossip.poll(owner.streams, clock)
  owner.preimages.poll(services[], owner.streams, clock)
  let acquired = owner.preimages.takeAcquired()
  if acquired.error == ReadError.None and owner.preimages.has(acquired.value):
    discard owner.gossip.offer(owner.streams, acquired.value) # Fresh state/possession checks remain required before transmission.
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
      if completed.kind == ProofWorkerCompletionKind.TicketVerified and owner.streams.readLive(
          owner.readTicket):
        let accepted = owner.finishTicket(completed.verifiedTicketValue, now)
        if accepted:
          let reply = captureReadReply(owner.pendingRequest, [])
          if reply.error != ReadError.None:
            discard owner.streams.reject(owner.readTicket) # A failed frozen acknowledgment never exposes an empty default reply.
          elif owner.streams.respond(owner.readTicket, reply.value) != ReadError.None:
            discard owner.streams.reject(owner.readTicket) # Output pressure retires the exact claimed stream.
        else:
          discard owner.streams.reject(owner.readTicket) # Epoch/window/context failures expose no accepted ticket prefix or success FIN.
      elif completed.kind == ProofWorkerCompletionKind.ReadCompleted and
          completed.readValue.error == ReadError.None and owner.streams.readLive(owner.readTicket):
        let reply = completed.readValue.value
        var accepted = true
        if reply.effect == ReadEffect.FetchPreimage:
          let notice = decodeAnnouncement(owner.pendingRequest.payload)
          accepted = notice.error == ReadError.None
          if accepted:
            accepted = owner.preimages.enqueue(owner.streams, owner.readTicket.sourcePeer,
                notice.value, clock)
            if accepted and owner.preimages.has(notice.value):
              discard owner.gossip.offer(owner.streams,
                  notice.value) # Cached reception can announce a separately requested service namespace.
        if not accepted or owner.streams.respond(owner.readTicket, reply) != ReadError.None:
          discard owner.streams.reject(owner.readTicket) # Exhausted followup/output capacity never acknowledges unowned work.
      else:
        discard owner.streams.reject(owner.readTicket) # Cancellation/stale collection never emits a successful response prefix.
    else:
      discard owner.streams.reject(owner.readTicket) # External joined Services shutdown has already retired the old worker.
    owner.clearJob()
  if not services[].stateProofAvailable: return true # Foreign RPC/preparation/publication leases remain untouched.
  if owner.refresh(now) != NodeError.None: return false
  owner.refreshTickets(now) # All detached source aliases retire before any subsequent worker admission.
  owner.dispatchTickets(now, clock) # Finality/context checks precede every actual proxy transmission.
  owner.dispatchGossip(clock) # The staging activation retires all canonical aliases before CPU admission.
  if owner.preferFetch and owner.preimages.submitWaiting(services[]):
    owner.preferFetch = false
    return true
  if owner.preferChecked and owner.submitChecked(): return true
  let request = owner.streams.takeRead()
  if request.error != NodeError.None:
    if not owner.submitChecked(): discard owner.preimages.submitWaiting(services[])
    return true
  if owner.serveCached(request.value): return true
  if not owner.beginIncoming(request.value, now):
    discard owner.streams.reject(request.value.ticket) # Busy/missing/invalid semantic admission never fabricates an empty successful response.
  true
