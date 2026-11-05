# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional main-thread CE134 orchestration retains only exact tokens, fixed targets and detached bytes; Services owns every credential/source graph.
## Report computation, signing, receiving, peer verification and collection run only through closed managed jobs.
import std/[assertions, monotimes, times]
import ./services
import ./proof/work_submission
import ../jamnp-s/[node, connections, work_sharing, work_guarantee, work_signer,
  sharing_client, read_stream, endpoints]
import ../codec/bounded
import ../codec/state/safrole

type
  WorkExchangePolicy* = object ## Explicit local limits are independent from transport bytes and source-derived consensus parameters.
    ready: bool
    limits: WorkSharingLimits
    guarantee: ByteLimit
    timeout, peerTimeout, grace: int
  WorkExchangePhase* {.pure.} = enum ## Ready means collected signatures, not fresh block admission or completed CE135 distribution.
    Idle, Reporting, Signing, Preparing, Exchanging, Checking, Collecting, Ready, Retiring
  PeerPhase {.pure.} = enum ## Each of at most two targets has one bounded native request and one verification outcome.
    Waiting, Connecting, Requested, ResponseReady, Verifying, Accepted, Refused
  ExchangePeer = object ## Fixed untrusted response and exact native/dial tokens retain no canonical or signer alias.
    phase: PeerPhase
    request: NodeSharingRequestTicket
    dial: DialTicket
    dialing: bool
    started: MonoTime
    identity, dialIdentity: StateEdKey
    response: array[96, byte]
  WorkExchangeDispatcher* = object ## Noncopyable exact-session control cannot abandon or duplicate another controller's CPU/native lifetime.
    policy: WorkExchangePolicy
    phase: WorkExchangePhase
    session: WorkSessionToken
    started, graceStarted: MonoTime
    grace: bool
    peers: array[2, ExchangePeer]
    checking, cursor: int
    incoming: NodeSharingTicket
    incomingToken: WorkSharingToken
    incomingActive, incomingCancelled, preferIncoming: bool
    received, collected: uint64
func workExchangePolicy*(limits: WorkSharingLimits, guaranteeBytes: ByteLimit,
    timeoutMs: range[2001..120000] = 120000, peerTimeoutMs: range[1..120000] = 10000,
    graceMs: range[2000..120000] = 2000): WorkExchangePolicy =
  ## At least two seconds gives the third guarantor a reasonable response opportunity; every allocation/stage still has explicit child bounds.
  if uint64(limits.packageBytes) == 0 or uint64(limits.bundleBytes) == 0: return default(WorkExchangePolicy)
  if uint64(limits.report.reportBytes) == 0 or uint64(limits.eligibility.reportBytes) == 0:
    return default(WorkExchangePolicy)
  if uint64(guaranteeBytes) == 0 or timeoutMs <= graceMs: return default(WorkExchangePolicy)
  WorkExchangePolicy(ready: true, limits: limits, guarantee: guaranteeBytes,
    timeout: timeoutMs, peerTimeout: peerTimeoutMs, grace: graceMs)
func valid*(policy: WorkExchangePolicy): bool =
  ## Omission never enables signed exchange or incoming sharing handlers.
  policy.ready
func phase*(owner: WorkExchangeDispatcher): WorkExchangePhase =
  ## Only fixed host state is observable through foreign CPU leases.
  owner.phase
func configured*(owner: WorkExchangeDispatcher): bool =
  ## Native admission requires a real configured managed consumer.
  owner.policy.ready
func received*(owner: WorkExchangeDispatcher): uint64 =
  ## Count only genuine collected incoming signatures whose fixed response was accepted by the live native route.
  owner.received
func collected*(owner: WorkExchangeDispatcher): uint64 =
  ## Count actual two/three-credential collections, without claiming distribution or on-chain admission.
  owner.collected
proc `=copy`*(destination: var WorkExchangeDispatcher, source: WorkExchangeDispatcher) {.error.}
  ## Duplicating a session/worker/dial controller would create competing retirement authority.
proc `=dup`*(source: WorkExchangeDispatcher): WorkExchangeDispatcher {.error.}
  ## Initialization cannot duplicate the live controller either.
proc `=wasMoved`*(owner: var WorkExchangeDispatcher) {.nodestroy, requires:
    owner.phase == WorkExchangePhase.Idle and not owner.incomingActive.} =
  ## Every owned child transfers only after all exact controls have retired.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.session)
  `=wasMoved`(owner.peers)
  `=wasMoved`(owner.incoming)
  `=wasMoved`(owner.incomingToken)
  owner.incomingActive = false
  owner.phase = WorkExchangePhase.Idle
proc requireClosed(owner: WorkExchangeDispatcher) {.requires:
    owner.phase == WorkExchangePhase.Idle and not owner.incomingActive.} =
  ## Explicit close/release cannot be replaced by silently abandoning a canonical borrower.
  discard
proc `=destroy`*(owner: WorkExchangeDispatcher) =
  ## Source-bearing state stays in Services; these child token owners retire only after explicit control teardown.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.session)
  `=destroy`(owner.peers)
  `=destroy`(owner.incoming)
  `=destroy`(owner.incomingToken)
proc configure*(owner: var WorkExchangeDispatcher, streams: var NodeService,
    policy: WorkExchangePolicy): bool =
  ## Install bounded consumers before native selectors are enabled; no partial/default policy is accepted.
  if not policy.ready or owner.policy.ready or owner.phase != WorkExchangePhase.Idle: return false
  if not streams.enableSharingStreams(): return false
  owner.policy = policy
  owner.preferIncoming = true
  true
proc beginCompleted*(owner: var WorkExchangeDispatcher, services: Services,
    token: WorkSessionToken, clock: MonoTime): bool =
  ## The exact retained builder completion supplies source authority; no caller-provided package/report is accepted here.
  if not owner.policy.ready or owner.phase != WorkExchangePhase.Idle: return false
  if services.workSessionPhase(token) != WorkSessionPhase.Complete: return false
  owner.session = token
  owner.started = clock
  owner.grace = false
  owner.peers = default(array[2, ExchangePeer])
  owner.phase = WorkExchangePhase.Reporting
  true
proc cancelPeers(owner: var WorkExchangeDispatcher, streams: var NodeService, force = false) =
  ## Request cancellation never owns an unrelated peer connection; only dials created by this exact round may be retired.
  for index in 0..<2:
    discard streams.cancelSharingRequest(owner.peers[index].request)
    let idle = not streams.peerBusy(owner.peers[index].dialIdentity)
    if owner.peers[index].dialing and (force or idle):
      discard streams.cancelPeerConnection(owner.peers[index].dial)
      owner.peers[index].dialing = false
proc retire(owner: var WorkExchangeDispatcher, services: var Services, streams: var NodeService) =
  ## Scalar retirement is immediate while Services defers all shared graph release through exact collection/join.
  owner.cancelPeers(streams)
  discard services.retireWorkSubmission(owner.session)
  owner.phase = WorkExchangePhase.Retiring
proc release*(owner: var WorkExchangeDispatcher, services: var Services,
    streams: var NodeService): bool =
  ## A downstream consumer can release only this controller's own retained session.
  if owner.phase == WorkExchangePhase.Idle: return false
  owner.retire(services, streams)
  true
proc pollIncoming(owner: var WorkExchangeDispatcher, services: var Services,
    streams: var NodeService) =
  ## Native reset or external joined stop cannot expose a signature prefix or retain an orphaned sharing namespace.
  if not owner.incomingActive: return
  if not services.workSharingActive(owner.incomingToken):
    discard streams.rejectSharing(owner.incoming)
    owner.incomingActive = false
    return
  if not streams.sharingLive(owner.incoming) and not owner.incomingCancelled:
    owner.incomingCancelled = services.cancelWorkSharing(owner.incomingToken)
  let completed = services.collectWorkSharing(owner.incomingToken)
  if completed.kind == WorkSharingCompletionKind.Uninitialized: return
  if completed.kind == WorkSharingCompletionKind.Completed and streams.sharingLive(owner.incoming):
    if streams.respondSharing(owner.incoming, completed.response) == ReadError.None:
      if owner.received < high(uint64): inc owner.received
    else:
      discard streams.rejectSharing(owner.incoming) # Output pressure cannot manufacture success FIN.
  else:
    discard streams.rejectSharing(owner.incoming) # Refusal/cancellation produces no hash/signature response.
  owner.incomingActive = false
  owner.incomingCancelled = false
proc pollPeers(owner: var WorkExchangeDispatcher, services: Services,
    streams: var NodeService, clock: MonoTime) =
  ## Two source-free native directions progress even when canonical/round graphs belong to a foreign worker.
  let count = services.workExchangeInfo(owner.session).targets
  for index in 0..<count:
    let peer = addr owner.peers[index]
    if peer.phase == PeerPhase.Requested:
      let completed = streams.takeSharingReply(peer.request)
      if completed.error == ReadError.None:
        peer.identity = peer.request.peerIdentity
        peer.response = completed.value.bytes
        peer.phase = PeerPhase.ResponseReady
      elif completed.error != ReadError.Unavailable or (clock-peer.started).inMilliseconds >=
          owner.policy.peerTimeout:
        discard streams.cancelSharingRequest(peer.request)
        peer.phase = PeerPhase.Refused
    elif peer.phase == PeerPhase.Connecting:
      if not streams.peerConnectionLive(peer.dial) or (clock-peer.started).inMilliseconds >=
          owner.policy.peerTimeout:
        if not streams.peerBusy(peer.dialIdentity):
          discard streams.cancelPeerConnection(peer.dial)
          peer.dialing = false
        peer.phase = PeerPhase.Refused # A remote stream keeps an owned demand connection until safe round retirement.
proc poll*(owner: var WorkExchangeDispatcher, services: var Services, streams: var NodeService,
    clock: MonoTime) =
  ## Collection and raw I/O occur before application arbitration; this method never admits a new CPU job.
  if not owner.policy.ready: return
  owner.pollIncoming(services, streams)
  if owner.phase == WorkExchangePhase.Idle: return
  let current = services.collectWorkSubmission(owner.session)
  if owner.phase == WorkExchangePhase.Retiring:
    let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeout
    owner.cancelPeers(streams, expired) # Continuous remote traffic cannot extend this round's owned connection lifetime past its explicit deadline.
    let dialing = owner.peers[0].dialing or owner.peers[1].dialing
    if not dialing and not services.workSubmissionActive(owner.session):
      discard services.reapWorkSubmission()
      owner.session = default(WorkSessionToken)
      owner.peers = default(array[2, ExchangePeer])
      owner.phase = WorkExchangePhase.Idle
    return
  if current in [WorkSessionPhase.Empty, WorkSessionPhase.Failed, WorkSessionPhase.Retired]:
    owner.retire(services, streams)
    return
  if (clock-owner.started).inMilliseconds >= owner.policy.timeout:
    owner.retire(services, streams)
    return
  case owner.phase
  of WorkExchangePhase.Reporting:
    if current == WorkSessionPhase.ReportReady: owner.phase = WorkExchangePhase.Signing
  of WorkExchangePhase.Signing:
    if current == WorkSessionPhase.Contributed: owner.phase = WorkExchangePhase.Preparing
  of WorkExchangePhase.Preparing:
    if current == WorkSessionPhase.AwaitingContributions: owner.phase = WorkExchangePhase.Exchanging
  of WorkExchangePhase.Checking:
    if current == WorkSessionPhase.AwaitingContributions:
      let info = services.workExchangeInfo(owner.session)
      owner.peers[owner.checking].phase = if info.status == WorkJobResultKind.PeerAccepted:
        PeerPhase.Accepted else: PeerPhase.Refused
      owner.phase = WorkExchangePhase.Exchanging
  of WorkExchangePhase.Collecting:
    if current == WorkSessionPhase.Guaranteed:
      owner.phase = WorkExchangePhase.Ready
      if owner.collected < high(uint64): inc owner.collected
  else: discard # Waiting/raw/ready states neither inspect source graphs nor consume unrelated leases.
  if owner.phase in [WorkExchangePhase.Exchanging, WorkExchangePhase.Checking]:
    owner.pollPeers(services, streams, clock)
  if owner.phase != WorkExchangePhase.Exchanging: return
  let info = services.workExchangeInfo(owner.session)
  var responseReady = false
  var possible = false
  for index in 0..<info.targets:
    if owner.peers[index].phase == PeerPhase.ResponseReady: responseReady = true
    if owner.peers[index].phase notin [PeerPhase.Accepted, PeerPhase.Refused]: possible = true
  if info.credentials >= 2:
    if not owner.grace:
      owner.grace = true
      owner.graceStarted = clock
    let expired = (clock-owner.graceStarted).inMilliseconds >= owner.policy.grace
    if info.credentials == 3 or (expired and not responseReady): owner.phase = WorkExchangePhase.Collecting
  elif not possible:
    owner.retire(services, streams) # No remaining actual target can supply the missing second credential.
proc submitIncoming(owner: var WorkExchangeDispatcher, services: var Services,
    streams: var NodeService, now: StateTime): bool {.raises.} =
  ## Claim at most one complete authenticated raw request only when the single managed CPU is available.
  if owner.incomingActive: return false
  let task = streams.takeSharingRequest()
  if task.error != NodeError.None: return false
  let admitted = services.beginWorkSharing(task.value.request, streams.localIdentity,
    task.value.peerIdentity,
    now, owner.policy.limits)
  if admitted.error != StateProofAdmissionError.None:
    discard streams.rejectSharing(task.value.ticket)
    return false
  owner.incoming = task.value.ticket
  owner.incomingToken = admitted.value
  owner.incomingActive = true
  owner.incomingCancelled = false
  true
proc requestPeer(owner: var WorkExchangeDispatcher, services: Services, streams: var NodeService,
    index: int, clock: MonoTime) =
  ## A sealed fixed validator record selects both key and endpoint; peer announcements cannot replace either.
  let target = services.workShareTarget(owner.session, index).participant
  let peer = addr owner.peers[index]
  let existing = streams.peerForIdentity(target.validator.ed25519)
  if existing.error == NodeError.None:
    let requested = streams.requestSharing(existing.value, services.workSharingRequest(owner.session))
    if requested.error == NodeError.Unavailable or requested.error ==
        NodeError.LimitExceeded: return
    if requested.error != NodeError.None:
      peer.phase = PeerPhase.Refused
      return
    peer.request = requested.value
    peer.started = clock
    peer.phase = PeerPhase.Requested
    return
  if peer.phase == PeerPhase.Connecting: return
  let endpoint = validatorEndpoint(array[128, byte](target.validator.metadata))
  if endpoint.error != EndpointError.None:
    peer.phase = PeerPhase.Refused
    return
  let dial = streams.beginPeerConnection(target.validator.ed25519, endpoint.value)
  if dial.error == DialError.Unavailable: return # Another exact connection/open intent is bounded backpressure.
  if dial.error != DialError.None:
    peer.phase = PeerPhase.Refused
    return
  peer.dial = dial.value
  peer.dialIdentity = target.validator.ed25519
  peer.dialing = true
  peer.started = clock
  peer.phase = PeerPhase.Connecting
proc submitLocal(owner: var WorkExchangeDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime, now: StateTime): bool =
  ## Each arbiter turn admits at most one fixed closed job; no canonical alias survives the staging helper's return.
  var admitted = default(WorkSubmissionStart)
  case owner.phase
  of WorkExchangePhase.Reporting:
    if services.workSessionPhase(owner.session) != WorkSessionPhase.Complete: return false
    admitted = services.beginWorkReport(owner.session, owner.policy.limits.report, now)
  of WorkExchangePhase.Signing:
    if services.workSessionPhase(owner.session) != WorkSessionPhase.ReportReady: return false
    admitted = services.beginWorkContribution(owner.session, streams.localIdentity, now,
        owner.policy.limits.eligibility)
  of WorkExchangePhase.Preparing:
    if services.workSessionPhase(owner.session) != WorkSessionPhase.Contributed: return false
    admitted = services.beginWorkExchange(owner.session, owner.policy.limits.bundleBytes)
  of WorkExchangePhase.Exchanging:
    let count = services.workExchangeInfo(owner.session).targets
    for offset in 0..<count:
      let index = (owner.cursor+offset) mod count
      if owner.peers[index].phase == PeerPhase.ResponseReady:
        admitted = services.beginWorkPeerResponse(owner.session, index, owner.peers[index].identity,
          owner.peers[index].response)
        if admitted.error == StateProofAdmissionError.None:
          owner.checking = index
          owner.peers[index].phase = PeerPhase.Verifying
          owner.cursor = (index+1) mod count
          owner.phase = WorkExchangePhase.Checking
          return true
        return false
      if owner.peers[index].phase in [PeerPhase.Waiting, PeerPhase.Connecting]:
        owner.requestPeer(services, streams, index, clock)
    return false
  of WorkExchangePhase.Collecting:
    if services.workSessionPhase(owner.session) !=
        WorkSessionPhase.AwaitingContributions: return false
    admitted = services.beginWorkGuaranteeCollection(owner.session, owner.policy.guarantee)
  else: return false # Idle/ready/retiring states cannot manufacture or borrow execution authority.
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error != StateProofAdmissionError.None:
    owner.retire(services, streams)
    return false
  true
proc submit*(owner: var WorkExchangeDispatcher, services: var Services, streams: var NodeService,
    clock: MonoTime, now: StateTime): bool {.raises.} =
  ## Incoming requests and local pipeline stages alternate when both are runnable; ordinary application arbitration remains outside.
  if not owner.policy.ready or not services.stateProofAvailable: return false
  if owner.preferIncoming and owner.submitIncoming(services, streams, now):
    owner.preferIncoming = false
    return true
  if owner.submitLocal(services, streams, clock, now):
    owner.preferIncoming = true
    return true
  if owner.submitIncoming(services, streams, now):
    owner.preferIncoming = false
    return true
  false
proc close*(owner: var WorkExchangeDispatcher, services: var Services, streams: var NodeService) =
  ## Join only an exact owned CPU turn; foreign graph borrowers keep their normal lifetime and deferred Services retirement.
  if owner.incomingActive:
    if services.cancelWorkSharing(owner.incomingToken): services.stopStateProofs()
    discard streams.rejectSharing(owner.incoming)
    owner.incomingActive = false
  if owner.phase != WorkExchangePhase.Idle:
    let own = services.workSubmissionActive(owner.session)
    owner.retire(services, streams)
    if own: services.stopStateProofs()
    discard services.reapWorkSubmission()
  for index in 0..<2:
    # Whole-host shutdown retires every incoming route too, so no remote stream survives this final connection cleanup.
    if owner.peers[index].dialing:
      discard streams.cancelPeerConnection(owner.peers[index].dial)
  owner.session = default(WorkSessionToken)
  owner.peers = default(array[2, ExchangePeer])
  owner.incoming = default(NodeSharingTicket)
  owner.incomingToken = default(WorkSharingToken)
  owner.incomingCancelled = false
  owner.policy = default(WorkExchangePolicy)
  owner.phase = WorkExchangePhase.Idle
