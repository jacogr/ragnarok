# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Foreground controller for qualified negative-report obligations.
import std/[monotimes, times]
import ./[services, audit_state, audit_acquisition, judgment_distribution]
import ./proof/worker
import ../jamnp-s/[node, audit_registry, audit_participation, audit_publication,
    judgment_gossip, judgment_receipt]

type
  ForcedAuditPolicy* = object
    ready: bool
    acquisition: AuditAcquisitionPolicy
    participation: AuditParticipationLimits
    publication: AuditPublicationLimits
    gossip: JudgmentGossipPolicy
  Phase {.pure.} = enum
    Idle, Planning, Acquire, Acquiring, Sign, Signing, Publish
  ForcedAudits* = object
    policy: ForcedAuditPolicy
    gossip: JudgmentGossip
    phase: Phase
    cursor, row, validator: int
    source: AuditOriginId
    proof: ProofWorkerTicket
    plan: AuditParticipationPlan
    publication: AuditPublication
    completed: array[256, bool]
    retry: array[256, MonoTime]

func forcedAuditPolicy*(acquisition: AuditAcquisitionPolicy,
    participation: AuditParticipationLimits,

publication: AuditPublicationLimits, gossip: JudgmentGossipPolicy): ForcedAuditPolicy =
  ## Validate each policy before enabling automatic work.
  if not acquisition.valid or not participation.valid or not publication.valid or not gossip.valid:
    return default(ForcedAuditPolicy)
  ForcedAuditPolicy(ready: true, acquisition: acquisition, participation: participation,
    publication: publication, gossip: gossip)

proc `=copy`*(destination: var ForcedAudits, source: ForcedAudits) {.error.}
proc `=dup`*(source: ForcedAudits): ForcedAudits {.error.}
proc `=wasMoved`*(owner: var ForcedAudits) {.nodestroy, requires: owner.phase == Phase.Idle.} =
  `=wasMoved`(owner.gossip)
  `=wasMoved`(owner.source)
  `=wasMoved`(owner.proof)
  `=wasMoved`(owner.plan)
  `=wasMoved`(owner.publication)
proc requireIdle(owner: ForcedAudits) {.requires: owner.phase == Phase.Idle.} = discard
proc `=destroy`*(owner: ForcedAudits) =
  requireIdle(owner)
  `=destroy`(owner.gossip)
  `=destroy`(owner.source)
  `=destroy`(owner.proof)
  `=destroy`(owner.plan)
  `=destroy`(owner.publication)

func ownsAcquisition*(owner: ForcedAudits): bool =
  owner.phase == Phase.Acquiring

proc configure*(owner: var ForcedAudits, services: Services, streams: NodeService,
    receipt: JudgmentDispatcher, policy: ForcedAuditPolicy): bool =
  ## Bind automatic signing to the configured TLS identity.
  if owner.policy.ready or not policy.ready or not receipt.configured or not streams.isOpen:
    return false
  if not services.auditSigningMatches(streams.localIdentity): return false
  if not owner.gossip.configure(policy.gossip): return false
  owner.policy = policy
  true

proc clear(owner: var ForcedAudits) =
  owner.phase = Phase.Idle
  owner.source = default(AuditOriginId)
  owner.proof = default(ProofWorkerTicket)
  owner.plan = default(AuditParticipationPlan)
  owner.publication = default(AuditPublication)

proc finish(owner: var ForcedAudits, clock: MonoTime, complete: bool) =
  ## Keep unavailable work eligible after a bounded delay.
  owner.completed[owner.row] = complete
  owner.retry[owner.row] = clock+initDuration(seconds = 1)
  owner.clear()

proc poll*(owner: var ForcedAudits, services: var Services, streams: var NodeService,
    receipt: var JudgmentDispatcher, acquisition: AuditAcquisition, clock: MonoTime) =
  ## Collect the exact managed worker generation before advancing the obligation.
  if not owner.policy.ready: return
  owner.gossip.poll(streams, clock)
  case owner.phase
  of Phase.Planning, Phase.Signing:
    if not services.stateProofActive(owner.proof):
      owner.finish(clock, false)
      return
    let outcome = services.collectAudit(owner.proof)
    if outcome.kind == ManagedAuditKind.Uninitialized: return
    if owner.phase == Phase.Planning and outcome.kind == ManagedAuditKind.ParticipationPlanned:
      owner.plan = outcome.participationPlan
      if owner.plan.participationInfo.value.localValidators == 0:
        owner.finish(clock, true)
        return
      let record = receipt.pendingAt(owner.row).judgment
      if not owner.gossip.offer(record, owner.plan, JudgmentDeliveryMode.Relayed):
        owner.finish(clock, false)
        return
      owner.phase = Phase.Acquire
    elif owner.phase == Phase.Signing and outcome.kind == ManagedAuditKind.PublicationPrepared:
      if outcome.publicationId != owner.source or outcome.publicationOrdinal != 0:
        owner.finish(clock, false)
        return
      owner.publication = outcome.preparedPublication
      owner.phase = Phase.Publish
    else:
      owner.finish(clock, false)
  of Phase.Acquiring:
    if acquisition.busy: return
    if acquisition.phase == AuditAcquisitionPhase.Complete:
      owner.validator = 0
      owner.phase = Phase.Sign
    else:
      owner.finish(clock, false)
  of Phase.Publish:
    if not receipt.rememberPublication(owner.publication): return
    let record = qualifyLocalJudgment(owner.publication.signedJudgment).value
    if not owner.gossip.offer(record, owner.plan, JudgmentDeliveryMode.Produced): return
    owner.publication = default(AuditPublication)
    inc owner.validator
    if owner.validator == owner.plan.participationInfo.value.localValidators:
      owner.finish(clock, true)
    else:
      owner.phase = Phase.Sign
  else: discard

proc submit*(owner: var ForcedAudits, services: var Services, streams: NodeService,
    receipt: JudgmentDispatcher, acquisition: var AuditAcquisition,
        clock: MonoTime): bool {.raises.} =
  ## Admit one operation per foreground arbitration turn.
  if not owner.policy.ready or not services.stateProofAvailable: return false
  case owner.phase
  of Phase.Idle:
    let count = receipt.pendingCount
    if count == 0: return false
    owner.cursor = owner.cursor mod count
    for turn in 0..<count:
      let row = owner.cursor
      owner.cursor = (row+1) mod count
      if owner.completed[row] or clock < owner.retry[row]: continue
      owner.row = row
      owner.source = receipt.pendingAt(row).originId
      let started = services.beginAuditParticipation(owner.source, 0, streams.localIdentity,
        owner.policy.participation)
      if started.error == StateProofAdmissionError.Busy: return false
      if started.error != StateProofAdmissionError.None:
        owner.finish(clock, false)
        return false
      owner.proof = started.value
      owner.phase = Phase.Planning
      return true
  of Phase.Acquire:
    if acquisition.begin(owner.policy.acquisition, owner.source, 0, clock):
      owner.phase = Phase.Acquiring
      return true
  of Phase.Sign:
    let index = owner.plan.localValidatorAt(owner.validator).value
    let started = services.beginAuditPublication(owner.source, 0, index, owner.policy.publication)
    if started.error == StateProofAdmissionError.Busy: return false
    if started.error != StateProofAdmissionError.None:
      owner.finish(clock, false)
      return false
    owner.proof = started.value
    owner.phase = Phase.Signing
    return true
  else: discard
  false

proc close*(owner: var ForcedAudits, services: var Services, streams: var NodeService) =
  ## ApplicationNode closes its acquisition owner separately.
  if owner.phase in {Phase.Planning, Phase.Signing} and services.stateProofActive(owner.proof):
    if services.cancelStateProof(owner.proof): services.stopStateProofs()
  owner.gossip.close(streams)
  owner.clear()
  owner.policy = default(ForcedAuditPolicy)
  owner.cursor = 0
  owner.completed = default(array[256, bool])
  owner.retry = default(array[256, MonoTime])
