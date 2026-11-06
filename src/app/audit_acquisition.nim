# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional bounded CE147-to-CE138 acquisition owns one original report obligation, exact native tickets and private Services jobs. Callbacks retain bytes only; timeouts and exhausted peers never produce invalid judgments.
import std/[monotimes, times]
import ./[services, audit_state]
import ./proof/worker
import ../jamnp-s/[audit_fetch, audit_registry, audit_evaluation, audit_recovery,
  availability_proof, node, connections, read_stream, read_client, endpoints]
import ../codec/bounded
import ../codec/state/safrole
import ../state/erasure/layout

type
  AuditAcquisitionLimits* = object ## Whole-round ceilings accompany independent maintained per-operation policies.
    fetch*: AuditFetchLimits
    evaluation*: AuditEvaluationLimits
    recovery*: AuditRecoveryLimits
    transfer*: AvailabilityMerkleLimits
    bytes*, hashBytes*: ByteLimit
    hashes*, requests*: ElementLimit
    timeoutMs*, peerTimeoutMs*: int
  AuditAcquisitionPolicy* = object ## Omission never starts retrieval or reserves a worker/native stream.
    ready: bool
    limits: AuditAcquisitionLimits
  AuditAcquisitionPhase* {.pure.} = enum ## Terminal unavailable/cancelled observations contain no report-invalid authority.
    Idle, PlanReady, Planning, Network, VerifyReady, Verifying, EvaluateReady,
    Evaluating, RecoverReady, Recovering, Complete, Unavailable, Cancelled
  AuditAcquisitionInfo* = object ## Detached lifecycle counters aid bounded progress diagnostics without exposing source or native tokens.
    phase*: AuditAcquisitionPhase
    target*, attempts*, shards*: int
    recovery*: bool
  AuditAcquisition* = object ## Noncopyable exact control ownership is separate from immutable detached plan/proof children.
    policy: AuditAcquisitionPolicy
    phase: AuditAcquisitionPhase
    id: AuditOriginId
    ordinal, target: int
    recovery, active, cancelling, dialing, closingDial, requested, advancing, probe: bool
    plan: AuditFetchPlan
    packets: seq[VerifiedAvailabilityTransfer]
    wire: seq[byte]
    proof: ProofWorkerTicket
    request: NodeRequestTicket
    dial: DialTicket
    dialIdentity: StateEdKey
    started, peerStarted: MonoTime
    facts: AuditEvaluationInfo
    attempts: int
func auditAcquisitionPolicy*(limits: AuditAcquisitionLimits): AuditAcquisitionPolicy =
  ## Finite explicit caps leave defaults inactive; full-source registry admission remains an independent Services prerequisite.
  if not limits.fetch.valid or not limits.evaluation.valid or not limits.recovery.valid:
    return default(AuditAcquisitionPolicy)
  if uint64(limits.bytes) < uint64(limits.fetch.bytes)+4096 or
      uint64(limits.bytes) > 1024'u64*1024*1024:
    return default(AuditAcquisitionPolicy)
  if uint64(limits.hashes) == 0 or uint64(limits.hashBytes) == 0:
    return default(AuditAcquisitionPolicy)
  if uint64(limits.requests) == 0 or uint64(limits.requests) > 3072:
    return default(AuditAcquisitionPolicy)
  if limits.timeoutMs < 1 or limits.timeoutMs > 120000 or limits.peerTimeoutMs < 1 or
      limits.peerTimeoutMs > limits.timeoutMs:
    return default(AuditAcquisitionPolicy)
  if uint64(limits.transfer.bytes) == 0 or uint64(limits.transfer.bytes) > 256'u64*1024*1024 or
      uint64(limits.transfer.hashes) == 0 or uint64(limits.transfer.hashes) > 1000000 or
      uint64(limits.transfer.hashBytes) == 0 or uint64(limits.transfer.hashBytes) >
          128'u64*1024*1024:
    return default(AuditAcquisitionPolicy)
  AuditAcquisitionPolicy(ready: true, limits: limits)
func valid*(policy: AuditAcquisitionPolicy): bool =
  ## A default policy confers no network or execution admission.
  policy.ready
func phase*(owner: AuditAcquisition): AuditAcquisitionPhase =
  ## Fixed host state is safe during unrelated canonical leases.
  owner.phase
func acquisitionInfo*(owner: AuditAcquisition): AuditAcquisitionInfo =
  ## Host-only counters stay independent of leased private source and proof payloads.
  AuditAcquisitionInfo(phase: owner.phase, target: owner.target, attempts: owner.attempts,
    shards: owner.packets.len, recovery: owner.recovery)
func inProgress(owner: AuditAcquisition): bool =
  ## A completed evaluation remains completed while native retirement drains; cleanup deadlines cannot change its actual validity observation.
  owner.phase in {AuditAcquisitionPhase.PlanReady, AuditAcquisitionPhase.Planning,
    AuditAcquisitionPhase.Network, AuditAcquisitionPhase.VerifyReady,
    AuditAcquisitionPhase.Verifying,
    AuditAcquisitionPhase.EvaluateReady, AuditAcquisitionPhase.Evaluating,
    AuditAcquisitionPhase.RecoverReady, AuditAcquisitionPhase.Recovering}
func busy*(owner: AuditAcquisition): bool =
  ## Exact native and managed controls must retire even after an unavailable terminal result.
  owner.active or owner.requested or owner.dialing or owner.inProgress
func evaluationInfo*(owner: AuditAcquisition): AuditEvaluationInfo {.requires: owner.phase ==
    AuditAcquisitionPhase.Complete.} =
  ## Actual completed evaluation facts are observations only; Services retains the private signing capability.
  owner.facts
proc `=copy`*(destination: var AuditAcquisition, source: AuditAcquisition) {.error.}
  ## Exact managed/native controls must never acquire a second cancelling owner.
proc `=dup`*(source: AuditAcquisition): AuditAcquisition {.error.}
  ## Construction cannot duplicate active or completed-uncollected controls.
proc requireClosed(owner: AuditAcquisition) {.requires: not owner.busy.} =
  ## Joined retirement precedes release of callback/controller storage.
  discard
proc `=wasMoved`*(owner: var AuditAcquisition) {.nodestroy, requires: not owner.busy.} =
  ## Delegate all owned children only after exact native/worker retirement.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.id)
  `=wasMoved`(owner.plan)
  `=wasMoved`(owner.packets)
  `=wasMoved`(owner.wire)
  `=wasMoved`(owner.proof)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.dial)
  `=wasMoved`(owner.dialIdentity)
  `=wasMoved`(owner.facts)
proc `=destroy`*(owner: AuditAcquisition) =
  ## Shutdown must retire every exact borrowed operation before destroying source-free child owners.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.id)
  `=destroy`(owner.plan)
  `=destroy`(owner.packets)
  `=destroy`(owner.wire)
  `=destroy`(owner.proof)
  `=destroy`(owner.request)
  `=destroy`(owner.dial)
  `=destroy`(owner.dialIdentity)
  `=destroy`(owner.facts)
proc begin*(owner: var AuditAcquisition, policy: AuditAcquisitionPolicy,
    id: AuditOriginId, ordinal: int, clock: MonoTime): bool =
  ## Host selectors grant no source authority; private lookup and full caps are checked during actual managed planning.
  if owner.busy or not policy.valid or ordinal < 0: return false
  owner.policy = policy
  owner.id = id
  owner.ordinal = ordinal
  owner.target = 0
  owner.recovery = false
  owner.cancelling = false
  owner.probe = true
  owner.advancing = false
  owner.closingDial = false
  owner.proof = default(ProofWorkerTicket)
  owner.request = default(NodeRequestTicket)
  owner.dial = default(DialTicket)
  owner.dialIdentity = default(StateEdKey)
  owner.plan = default(AuditFetchPlan)
  owner.packets = @[]
  owner.wire = @[]
  owner.facts = default(AuditEvaluationInfo)
  owner.attempts = 0
  owner.started = clock
  owner.peerStarted = clock
  owner.phase = AuditAcquisitionPhase.EvaluateReady
  true
proc retireNetwork(owner: var AuditAcquisition, streams: var NodeService, force: bool) =
  ## Cancel only this exact request/dial; established connections owned by other controllers remain live.
  if owner.requested:
    discard streams.cancelRequest(owner.request)
    owner.requested = false
    owner.request = default(NodeRequestTicket)
  if owner.dialing:
    if not streams.peerConnectionLive(owner.dial):
      owner.dialing = false
      owner.closingDial = false
      owner.dial = default(DialTicket)
    elif not owner.closingDial and (force or not streams.peerBusy(
        owner.dialIdentity)):
      owner.closingDial = streams.cancelPeerConnection(owner.dial)
proc reservePlan(owner: AuditAcquisition): bool =
  ## Reserve worst-case retained packets, raw replies, proof work and reconstruction before the first network attempt.
  let info = owner.plan.fetchInfo.value
  let limits = owner.policy.limits
  let count = uint64(info.assurers+info.guarantors)
  if count > uint64(limits.requests): return false
  if uint64(limits.transfer.hashes) > uint64(limits.hashes) div count: return false
  if uint64(limits.transfer.hashBytes) > uint64(limits.hashBytes) div count: return false
  let geometry = erasureGeometry(info.specifier.bundleLength, info.specifier.erasureShards).value
  # Geometry bounds N<=1023 and E4 length; all terms fit uint64 before comparison to the <=1GiB local cap.
  let retained = info.retainedBytes+(geometry.originalShards+1)*(geometry.bundleChunkBytes+4224)
  let scratch = uint64(limits.recovery.bytes)+uint64(limits.transfer.bytes)+3*uint64(
      limits.fetch.replyBytes)
  retained+scratch <= uint64(limits.bytes)
proc advanceTarget(owner: var AuditAcquisition, clock: MonoTime) =
  ## One peer failure advances an original row once; exhausting direct guarantors switches to independently proven shards.
  inc owner.target
  owner.peerStarted = clock
  owner.wire = @[]
  let info = owner.plan.fetchInfo.value
  if not owner.recovery and owner.target >= info.guarantors:
    owner.recovery = true
    owner.target = 0
  if owner.recovery and owner.target >= info.assurers:
    owner.phase = AuditAcquisitionPhase.Unavailable
  else:
    owner.phase = AuditAcquisitionPhase.Network
proc cancel*(owner: var AuditAcquisition, services: var Services, streams: var NodeService) =
  ## Cancellation withholds every successful prefix and keeps a live exact worker lease until collection or joined stop.
  owner.cancelling = true
  if owner.active: discard services.cancelStateProof(owner.proof)
  owner.retireNetwork(streams, true)
  if not owner.active: owner.phase = AuditAcquisitionPhase.Cancelled
proc collectWork(owner: var AuditAcquisition, services: var Services, clock: MonoTime) =
  ## Consume only this exact private managed completion; no generic collection can expose source-bearing evaluation owners.
  if not owner.active: return
  if not services.stateProofActive(owner.proof):
    owner.active = false
    owner.phase = AuditAcquisitionPhase.Cancelled
    return # Joined external stop revoked this physical generation without exposing its result.
  let completed = services.collectAudit(owner.proof)
  if completed.kind == ManagedAuditKind.Uninitialized: return
  owner.active = false
  owner.proof = default(ProofWorkerTicket)
  if owner.cancelling or completed.kind == ManagedAuditKind.Cancelled:
    owner.phase = AuditAcquisitionPhase.Cancelled
    return
  case owner.phase
  of AuditAcquisitionPhase.Planning:
    if completed.kind != ManagedAuditKind.FetchPlanned:
      owner.phase = AuditAcquisitionPhase.Unavailable
      return
    owner.plan = completed.fetchPlan
    if not owner.reservePlan:
      owner.phase = AuditAcquisitionPhase.Unavailable
      return
    owner.peerStarted = clock
    owner.phase = AuditAcquisitionPhase.Network
  of AuditAcquisitionPhase.Verifying:
    if completed.kind == ManagedAuditKind.ShardVerified:
      let packet = completed.verifiedShard
      var duplicate = false
      for prior in owner.packets:
        # Original-coordinate equality cannot be replaced by response ordering or peer key identity.
        if uint64(prior.request.shard) == uint64(packet.request.shard): duplicate = true
      if not duplicate: owner.packets.add(packet)
      if owner.packets.len == owner.plan.fetchInfo.value.threshold:
        owner.wire = @[]
        owner.phase = AuditAcquisitionPhase.RecoverReady
        return
    owner.advanceTarget(clock) # Invalid or unavailable shard evidence never reaches the private evaluator.
  of AuditAcquisitionPhase.Evaluating, AuditAcquisitionPhase.Recovering:
    if completed.kind == ManagedAuditKind.Evaluated:
      owner.facts = completed.evaluationInfo
      owner.wire = @[]
      owner.packets = @[]
      owner.phase = AuditAcquisitionPhase.Complete
    elif owner.phase == AuditAcquisitionPhase.Evaluating and
        completed.kind == ManagedAuditKind.EvaluationFailure and
            completed.evaluationError.needsRecovery:
      owner.wire = @[]
      if owner.probe:
        owner.probe = false
        owner.phase = AuditAcquisitionPhase.PlanReady
      else:
        owner.recovery = true
        owner.target = 0
        owner.peerStarted = clock
        owner.phase = AuditAcquisitionPhase.Network
    else:
      owner.phase = AuditAcquisitionPhase.Unavailable # Local quotas/history/backend failures and exhausted recovery are not negative judgments.
  else:
    owner.phase = AuditAcquisitionPhase.Unavailable # A foreign result kind never advances this acquisition.
proc poll*(owner: var AuditAcquisition, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Harvest exact completions and deadlines only; submit is a separate foreground arbitration step.
  if not owner.policy.ready: return
  let expired = (clock-owner.started).inMilliseconds >= owner.policy.limits.timeoutMs
  if expired:
    if owner.inProgress: owner.cancel(services, streams)
    else: owner.retireNetwork(streams, true) # Drain terminal native storage without discarding an actual completed evaluation.
  owner.collectWork(services, clock)
  if owner.cancelling:
    owner.retireNetwork(streams, true)
    return
  if owner.phase != AuditAcquisitionPhase.Network:
    owner.retireNetwork(streams, false)
    return
  if owner.dialing and owner.closingDial:
    owner.retireNetwork(streams, false)
    if not owner.dialing and owner.advancing:
      owner.advancing = false
      owner.advanceTarget(clock)
    return
  if owner.requested:
    let completed = streams.takeReply(owner.request)
    if completed.error == ReadError.None:
      owner.requested = false
      owner.request = default(NodeRequestTicket)
      owner.wire = completed.value.bytes
      if owner.recovery:
        owner.phase = AuditAcquisitionPhase.VerifyReady
      else:
        let candidate = owner.plan.directBundle(owner.wire)
        if candidate.error == AuditFetchError.None:
          owner.wire = candidate.value
          owner.phase = AuditAcquisitionPhase.EvaluateReady
        else:
          owner.recovery = true
          owner.target = 0
          owner.peerStarted = clock
          owner.wire = @[]
      owner.retireNetwork(streams, false)
    elif completed.error != ReadError.Unavailable or
        (clock-owner.peerStarted).inMilliseconds >= owner.policy.limits.peerTimeoutMs:
      owner.retireNetwork(streams, true)
      if not owner.dialing: owner.advanceTarget(clock)
      else: owner.advancing = true
    return
  if owner.dialing and (clock-owner.peerStarted).inMilliseconds >=
      owner.policy.limits.peerTimeoutMs:
    owner.retireNetwork(streams, true)
    if not owner.dialing: owner.advanceTarget(clock)
    else: owner.advancing = true
  elif not owner.dialing and (clock-owner.peerStarted).inMilliseconds >=
      owner.policy.limits.peerTimeoutMs:
    owner.advanceTarget(clock) # A busy native pool or an unavailable dial cannot strand one original target until the whole round expires.
proc submit*(owner: var AuditAcquisition, services: var Services,
    streams: var NodeService, clock: MonoTime): bool {.raises.} =
  ## Admit at most one fixed CPU turn or native attempt; unrelated actor leases remain untouched.
  if not owner.policy.ready or owner.cancelling or owner.active: return false
  if owner.phase == AuditAcquisitionPhase.Network:
    if owner.requested or owner.closingDial: return false
    let target = owner.plan.targetAt(owner.recovery, owner.target).value
    if array[32, byte](target.identity) == array[32, byte](streams.localIdentity):
      owner.advanceTarget(clock)
      return false # Local possession may be served separately; self-dial refusal cannot strand threshold acquisition.
    let existing = streams.peerForIdentity(target.identity)
    if existing.error == NodeError.None:
      let request = owner.plan.requestAt(owner.recovery, owner.target).value
      let admitted = streams.request(existing.value, request, owner.plan.replyLimit(owner.recovery))
      if admitted.error in [NodeError.Unavailable, NodeError.LimitExceeded]: return false
      if admitted.error != NodeError.None:
        owner.retireNetwork(streams, true)
        if not owner.dialing: owner.advanceTarget(clock)
        else: owner.advancing = true
        return false
      owner.request = admitted.value
      owner.requested = true
      owner.peerStarted = clock
      inc owner.attempts
      return true
    if owner.dialing: return false
    if target.endpoint.error != EndpointError.None or array[32, byte](target.identity) ==
        array[32, byte](nullValidator().ed25519) or array[32, byte](target.identity) == default(
            array[32, byte]):
      owner.advanceTarget(clock)
      return false
    let dial = streams.beginPeerConnection(target.identity, target.endpoint.value)
    if dial.error == DialError.Unavailable: return false
    if dial.error != DialError.None:
      owner.advanceTarget(clock)
      return false
    owner.dial = dial.value
    owner.dialIdentity = target.identity
    owner.dialing = true
    owner.closingDial = false
    owner.peerStarted = clock
    return true
  if not services.stateProofAvailable: return false
  var admitted = default(AuditPlanningStart)
  case owner.phase
  of AuditAcquisitionPhase.PlanReady:
    admitted = services.beginAuditFetchPlanning(owner.id, owner.ordinal, owner.policy.limits.fetch)
  of AuditAcquisitionPhase.VerifyReady:
    admitted = services.beginAuditShardVerification(owner.plan, owner.target, owner.wire,
        owner.policy.limits.transfer)
  of AuditAcquisitionPhase.EvaluateReady:
    admitted = services.beginAuditEvaluation(owner.id, owner.ordinal, owner.wire,
        owner.policy.limits.evaluation)
  of AuditAcquisitionPhase.RecoverReady:
    admitted = services.beginAuditRecoveryEvaluation(owner.id, owner.ordinal, owner.packets,
      owner.policy.limits.recovery, owner.policy.limits.evaluation)
  else: return false # Terminal/network-active phases cannot submit a new CPU job.
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error != StateProofAdmissionError.None:
    owner.phase = AuditAcquisitionPhase.Unavailable
    return false
  owner.proof = admitted.value
  owner.active = true
  case owner.phase
  of AuditAcquisitionPhase.PlanReady: owner.phase = AuditAcquisitionPhase.Planning
  of AuditAcquisitionPhase.VerifyReady: owner.phase = AuditAcquisitionPhase.Verifying
  of AuditAcquisitionPhase.EvaluateReady: owner.phase = AuditAcquisitionPhase.Evaluating
  else: owner.phase = AuditAcquisitionPhase.Recovering # Admission above proves RecoverReady is the sole remaining case.
  true
proc close*(owner: var AuditAcquisition, services: var Services, streams: var NodeService) =
  ## Successful exact cancellation authorizes joined retirement of this job; stale controls cannot stop another actor's lease.
  if owner.active:
    if services.cancelStateProof(owner.proof): services.stopStateProofs()
  owner.active = false
  owner.retireNetwork(streams, true)
  # Native dial cancellation revokes this controller's token immediately; NodeService retains physical buffers through callbacks.
  owner.dialing = false
  owner.closingDial = false
  owner.dial = default(DialTicket)
  owner.proof = default(ProofWorkerTicket)
  owner.plan = default(AuditFetchPlan)
  owner.packets = @[]
  owner.wire = @[]
  owner.id = default(AuditOriginId)
  owner.policy = default(AuditAcquisitionPolicy)
  owner.phase = AuditAcquisitionPhase.Idle
