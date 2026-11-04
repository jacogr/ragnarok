# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Main-thread builder dispatch owns detached wire and exact tokens; canonical grants/results remain private in Services.
import std/[monotimes, times, assertions]
import ./services
import ./work_policy/types as work_policy_types
export work_policy_types
import ../jamnp-s/[node, connections, work_submission, work_stream, work_duty, read_stream, read_client]
from ../codec/state/safrole import StateTime, StateEdKey

type
  WorkDispatchPhase* {.pure.} = enum ## Ready reserves the completed Services source until downstream processing releases it.
    Idle, Authorizing, Receiving, Acquiring, Completing, Ready, Retiring
  WorkDispatcher* = object ## Stable noncopyable token owner contains no canonical ARC owner or worker ticket.
    policy: WorkDispatchPolicy
    phase: WorkDispatchPhase
    session: WorkSessionToken
    network: NodeWorkTicket
    body: UntrustedWorkBody
    started: MonoTime
    accepted: uint64
    acquisition: WorkAcquisitionPolicy
    fetchRequest: ReadRequest
    fetchReply: seq[byte]
    tried: seq[StateEdKey]
    fetch: NodeRequestTicket
    fetchStarted: MonoTime
    fetching, requestPrepared, replyReady: bool
proc `=copy`*(destination: var WorkDispatcher, source: WorkDispatcher) {.error.}
  ## A second controller must never retire this controller's exact session.
proc `=dup`*(source: WorkDispatcher): WorkDispatcher {.error.}
  ## Default construction cannot duplicate live token ownership.
proc `=wasMoved`*(owner: var WorkDispatcher) {.nodestroy, requires: owner.phase ==
    WorkDispatchPhase.Idle.} =
  ## Only a retired controller may move; delegate every owned child explicitly.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.session)
  `=wasMoved`(owner.network)
  `=wasMoved`(owner.body)
  `=wasMoved`(owner.acquisition)
  `=wasMoved`(owner.fetchRequest)
  `=wasMoved`(owner.fetchReply)
  `=wasMoved`(owner.tried)
  `=wasMoved`(owner.fetch)
proc requireClosed(owner: WorkDispatcher) {.requires: owner.phase == WorkDispatchPhase.Idle.} =
  ## Destruction cannot abandon a selected Services session.
  discard
proc `=destroy`*(owner: WorkDispatcher) =
  ## Explicit close retires exact work before ordinary child destruction.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.session)
  `=destroy`(owner.network)
  `=destroy`(owner.body)
  `=destroy`(owner.acquisition)
  `=destroy`(owner.fetchRequest)
  `=destroy`(owner.fetchReply)
  `=destroy`(owner.tried)
  `=destroy`(owner.fetch)
func phase*(owner: WorkDispatcher): WorkDispatchPhase =
  ## Detached scalar state is safe during any foreign graph lease.
  owner.phase
func accepted*(owner: WorkDispatcher): uint64 =
  ## Count genuine refined transport acknowledgments, without claiming report or inclusion authority.
  owner.accepted
func completed*(owner: WorkDispatcher): WorkSessionToken {.requires: owner.phase ==
    WorkDispatchPhase.Ready.} =
  ## Downstream stages address the original retained result through Services rather than copying canonical ownership into this host.
  owner.session
proc configure*(owner: var WorkDispatcher, streams: var NodeService,
    policy: WorkDispatchPolicy): bool =
  ## Native route activation occurs only after installing the real bounded dispatcher.
  if not policy.valid or owner.policy.valid or owner.phase != WorkDispatchPhase.Idle: return false
  if not streams.enableWorkStreams(): return false
  owner.policy = policy
  owner.accepted = 0
  true
proc configureAcquisition*(owner: var WorkDispatcher, policy: WorkAcquisitionPolicy): bool =
  ## Optional acquisition can only be installed once, while no work session owns transport or CPU tokens.
  if not owner.policy.valid or not policy.valid or owner.acquisition.valid or owner.phase !=
      WorkDispatchPhase.Idle: return false
  owner.acquisition = policy
  true
proc clear(owner: var WorkDispatcher) =
  ## Only detached buffers and host token namespaces retire here; Services controls source graph retirement.
  owner.session = default(WorkSessionToken)
  owner.network = default(NodeWorkTicket)
  owner.body = default(UntrustedWorkBody)
  owner.fetchRequest = default(ReadRequest)
  owner.fetchReply = @[]
  owner.tried = @[]
  owner.fetch = default(NodeRequestTicket)
  owner.fetching = false
  owner.requestPrepared = false
  owner.replyReady = false
  owner.phase = WorkDispatchPhase.Idle
proc retire(owner: var WorkDispatcher, services: var Services, streams: var NodeService) =
  ## A reset or deadline cancels only this session; exact collection still precedes graph retirement.
  if owner.fetching:
    discard streams.cancelRequest(owner.fetch) # Only this controller's exact outbound token is cancelled.
    owner.fetching = false
  discard streams.rejectWork(owner.network)
  discard services.retireWorkSubmission(owner.session)
  owner.body = default(UntrustedWorkBody)
  owner.phase = WorkDispatchPhase.Retiring
proc release*(owner: var WorkDispatcher, services: var Services): bool =
  ## Downstream consumption explicitly releases the retained completion; no native success is fabricated.
  if owner.phase != WorkDispatchPhase.Ready: return false
  let ownActive = services.workSubmissionActive(owner.session)
  discard services.retireWorkSubmission(owner.session)
  if ownActive:
    owner.phase = WorkDispatchPhase.Retiring # Downstream report work still needs exact collection before this host may forget its session.
  else:
    owner.clear()
  true
proc close*(owner: var WorkDispatcher, services: var Services, streams: var NodeService) =
  ## Joined stop is permitted only when this exact session still owns the active CPU job.
  if owner.phase != WorkDispatchPhase.Idle:
    let ownActive = services.workSubmissionActive(owner.session)
    owner.retire(services, streams)
    if ownActive: services.stopStateProofs()
    discard services.reapWorkSubmission()
    owner.clear()
  owner.policy = default(WorkDispatchPolicy)
  owner.acquisition = default(WorkAcquisitionPolicy)
func currentDuty(services: Services, token: WorkSessionToken, now: StateTime): bool =
  ## Detached duty expiry never borrows selected state, even while a foreign worker owns it.
  services.workSubmissionDuty(token).activeAt(now)

proc alreadyTried(owner: WorkDispatcher, identity: StateEdKey): bool =
  ## A reconnect or changing peer ordinal cannot spend the bounded attempt budget repeatedly on the same identity.
  for previous in owner.tried:
    if array[32, byte](previous) == array[32, byte](identity): return true
  false
proc acquire(owner: var WorkDispatcher, services: var Services, streams: var NodeService,
    clock: MonoTime) =
  ## Host polling owns only detached request/reply bytes and exact tokens; roots and proof results remain inside Services.
  if not owner.requestPrepared:
    if not services.stateProofAvailable: return
    let planned = services.workImportRequest(owner.session)
    if planned.error != WorkSubmissionError.None:
      owner.retire(services, streams)
      return
    let described = services.workSubmissionInfo(owner.session)
    if uint64(8+described.segmentBytes+described.importCount) > uint64(
        owner.acquisition.replyBytes):
      owner.retire(services, streams)
      return
    if described.importCount == 0:
      owner.replyReady = true # Empty original manifests need no remote witness or fabricated successful reply.
    else:
      let request = decodeReadRequest(ReadKind.Segments, planned.value)
      if request.error != ReadError.None:
        owner.retire(services, streams)
        return
      owner.fetchRequest = request.value
    owner.requestPrepared = true
  if owner.replyReady:
    if not services.stateProofAvailable: return
    let started = services.beginFetchedWorkPackage(owner.session, owner.body.extrinsics,
        owner.fetchReply)
    if started.error == StateProofAdmissionError.Busy: return
    if started.error != StateProofAdmissionError.None:
      owner.retire(services, streams)
      return
    owner.body = default(UntrustedWorkBody)
    owner.fetchReply = @[] # Worker capture has its own bytes before this host buffer retires.
    owner.phase = WorkDispatchPhase.Completing
    return
  if owner.fetching:
    let reply = streams.takeReply(owner.fetch)
    if reply.error == ReadError.None:
      owner.fetchReply = reply.value.bytes
      owner.fetching = false
      owner.replyReady = true
      return
    let expired = (clock-owner.fetchStarted).inMilliseconds >= owner.acquisition.timeoutMs
    if not expired and streams.requestLive(owner.fetch): return
    discard streams.cancelRequest(owner.fetch)
    owner.fetching = false
  if owner.tried.len >= owner.acquisition.attempts:
    owner.retire(services, streams)
    return
  for index in 0..<streams.peerCount:
    # Scan only the transport's finite live population; no peer discovery or connection attempt is triggered by builder input.
    let selected = streams.peerAt(index)
    if selected.error != NodeError.None: continue
    let peer = selected.value
    if not streams.isValidator(peer) or owner.alreadyTried(peer.identity): continue
    let requested = streams.request(peer, owner.fetchRequest, owner.acquisition.replyBytes)
    if requested.error in [NodeError.LimitExceeded, NodeError.Unavailable]:
      continue # Shared reservations and an unfinished UP0 source handshake are backpressure, not a spent peer attempt.
    owner.tried.add(peer.identity)
    if requested.error != NodeError.None: return
    owner.fetch = requested.value
    owner.fetchStarted = clock
    owner.fetching = true
    return
proc poll*(owner: var WorkDispatcher, services: var Services, streams: var NodeService,
    clock: MonoTime, now: StateTime) =
  ## Bounded existing work advances independently of foreign CPU capacity; new header admission is a separate arbiter turn.
  if owner.phase in [WorkDispatchPhase.Idle, WorkDispatchPhase.Ready]: return
  if owner.phase != WorkDispatchPhase.Retiring:
    let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeoutMs
    if expired or not streams.workLive(owner.network): owner.retire(services, streams)
  let phase = services.collectWorkSubmission(owner.session)
  if owner.phase == WorkDispatchPhase.Retiring:
    # Exact collection may finish while a foreign lease keeps the retired context privately retained.
    if not services.workSubmissionActive(owner.session):
      discard services.reapWorkSubmission()
      owner.clear()
    return
  if phase in [WorkSessionPhase.Empty, WorkSessionPhase.Failed, WorkSessionPhase.Retired]:
    owner.retire(services, streams)
    return
  if phase == WorkSessionPhase.Authorizing: return
  if not services.currentDuty(owner.session, now):
    owner.retire(services, streams)
    return
  if owner.phase == WorkDispatchPhase.Authorizing and phase == WorkSessionPhase.Authorized:
    # Fixed geometry is safe to observe without borrowing the canonical grant.
    if streams.permitWorkBody(owner.network, services.workSubmissionInfo(owner.session)) !=
        ReadError.None:
      owner.retire(services, streams)
      return
    owner.phase = WorkDispatchPhase.Receiving
  if owner.phase == WorkDispatchPhase.Receiving:
    if not owner.body.valid:
      # No worker lease is held while the exact native stream awaits body bytes and FIN.
      let received = streams.takeWorkBody(owner.network)
      if received.error != NodeError.None: return
      owner.body = received.value
    if not services.stateProofAvailable: return
    if services.workSubmissionInfo(owner.session).kind == WorkSubmissionKind.Package:
      owner.phase = WorkDispatchPhase.Acquiring
      return
    let started = services.beginWorkBundle(owner.session, owner.body.extrinsics,
      owner.body.segments, owner.body.proofs)
    if started.error == StateProofAdmissionError.Busy: return
    if started.error != StateProofAdmissionError.None:
      owner.retire(services, streams)
      return
    owner.body = default(UntrustedWorkBody) # The worker retains independent byte copies, never this host's raw transcript.
    owner.phase = WorkDispatchPhase.Completing
    return
  if owner.phase == WorkDispatchPhase.Acquiring:
    owner.acquire(services, streams, clock)
    return
  if owner.phase == WorkDispatchPhase.Completing and phase == WorkSessionPhase.Complete:
    # Collection alone is insufficient after reset, source progress or rotation expiry.
    if not services.workSubmissionCurrent(owner.session):
      if not services.stateProofAvailable: return
      owner.retire(services, streams)
      return
    if streams.acknowledgeWork(owner.network) != ReadError.None:
      owner.retire(services, streams)
      return
    owner.phase = WorkDispatchPhase.Ready
    if owner.accepted < high(uint64): inc owner.accepted
proc submit*(owner: var WorkDispatcher, services: var Services, streams: var NodeService,
    clock: MonoTime, now: StateTime): bool {.raises.} =
  ## At most one new small header is claimed per arbiter turn, after every canonical staging alias has retired.
  if not owner.policy.valid or owner.phase != WorkDispatchPhase.Idle: return false
  if not services.stateProofAvailable: return false
  let task = streams.takeWorkHeader()
  if task.error != NodeError.None: return false
  if task.value.header.kind == WorkSubmissionKind.Package and not owner.acquisition.valid:
    discard streams.rejectWork(task.value.ticket) # Acquisition must have explicit independent local ceilings before CE133 activation.
    return true
  let started = services.beginWorkSubmission(task.value.header, owner.policy.admissionLimits,
    owner.policy.executionLimits, workRecipient(streams.localIdentity, now),
        owner.policy.dutyLimits)
  if started.error != StateProofAdmissionError.None:
    discard streams.rejectWork(task.value.ticket)
    return true
  owner.network = task.value.ticket
  owner.session = started.value
  owner.started = clock
  owner.phase = WorkDispatchPhase.Authorizing
  true
