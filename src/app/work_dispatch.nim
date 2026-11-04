# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Main-thread bundle dispatch owns detached wire and exact tokens; canonical grants/results remain private in Services.
import std/[monotimes, times, assertions]
import ./services
import ./work_policy/types as work_policy_types
export work_policy_types
import ../jamnp-s/[node, work_submission, work_stream, work_duty, read_stream]
from ../codec/state/safrole import StateTime

type
  WorkDispatchPhase* {.pure.} = enum ## Ready reserves the completed Services source until downstream processing releases it.
    Idle, Authorizing, Receiving, Completing, Ready, Retiring
  WorkDispatcher* = object ## Stable noncopyable token owner contains no canonical ARC owner or worker ticket.
    policy: WorkDispatchPolicy
    phase: WorkDispatchPhase
    session: WorkSessionToken
    network: NodeWorkTicket
    body: UntrustedWorkBody
    started: MonoTime
    accepted: uint64
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
proc clear(owner: var WorkDispatcher) =
  ## Only detached buffers and host token namespaces retire here; Services controls source graph retirement.
  owner.session = default(WorkSessionToken)
  owner.network = default(NodeWorkTicket)
  owner.body = default(UntrustedWorkBody)
  owner.phase = WorkDispatchPhase.Idle
proc retire(owner: var WorkDispatcher, services: var Services, streams: var NodeService) =
  ## A reset or deadline cancels only this session; exact collection still precedes graph retirement.
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
func currentDuty(services: Services, token: WorkSessionToken, now: StateTime): bool =
  ## Detached duty expiry never borrows selected state, even while a foreign worker owns it.
  services.workSubmissionDuty(token).activeAt(now)

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
    let started = services.beginWorkBundle(owner.session, owner.body.extrinsics,
      owner.body.segments, owner.body.proofs)
    if started.error == StateProofAdmissionError.Busy: return
    if started.error != StateProofAdmissionError.None:
      owner.retire(services, streams)
      return
    owner.body = default(UntrustedWorkBody) # The worker retains independent byte copies, never this host's raw transcript.
    owner.phase = WorkDispatchPhase.Completing
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
  if task.value.header.kind != WorkSubmissionKind.Bundle:
    discard streams.rejectWork(task.value.ticket) # CE133 requires real availability acquisition before this dispatcher can serve it.
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
