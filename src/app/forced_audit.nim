# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Foreground controller for qualified negative-report obligations.
import std/[monotimes, times]
import ./[services, audit_state, audit_acquisition, judgment_distribution, initial_audit]
from ../codec/state/safrole import StateValidatorIndex
import ./proof/worker
import ../chain/genesis
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
    Idle, Planning, Acquire, Acquiring, Sign, Signing, Publish, Refreshing
  DeclaredProgress = object ## One declaration's next report and retry deadline.
    selected: int
    retry: MonoTime
  RefreshRecord = object ## Detached signed evidence and a private origin selector allow a later topology-only job.
    record: QualifiedJudgment
    basis: AuditRoutingBasis
    mode: JudgmentDeliveryMode
    awaiting: bool
    head: genesis.BlockHash
    retry: MonoTime
  ForcedAudits* = object
    policy: ForcedAuditPolicy
    gossip: JudgmentGossip
    phase: Phase
    cursor, row, validator, reportOrdinal: int
    declared, preferDeclared: bool
    declaration, declarationCursor: int
    declaredProgress: array[256, DeclaredProgress]
    originalValidator: StateValidatorIndex
    publishDeadline: MonoTime
    source, releasable: AuditOriginId
    proof: ProofWorkerTicket
    plan: AuditParticipationPlan
    publication: AuditPublication
    completed: array[256, bool]
    retry: array[256, MonoTime]
    refresh: seq[RefreshRecord]
    refreshCursor, refreshing: int
    preferRefresh: bool

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
  `=wasMoved`(owner.releasable)
  `=wasMoved`(owner.proof)
  `=wasMoved`(owner.plan)
  `=wasMoved`(owner.publication)
  `=wasMoved`(owner.refresh)
proc requireIdle(owner: ForcedAudits) {.requires: owner.phase == Phase.Idle.} = discard
proc `=destroy`*(owner: ForcedAudits) =
  requireIdle(owner)
  `=destroy`(owner.gossip)
  `=destroy`(owner.source)
  `=destroy`(owner.releasable)
  `=destroy`(owner.proof)
  `=destroy`(owner.plan)
  `=destroy`(owner.publication)
  `=destroy`(owner.refresh)

func canExpire*(owner: ForcedAudits): bool =
  ## A leased or scheduled report still depends on its original registry and queue positions.
  owner.phase == Phase.Idle
proc releaseDeclaredOrigins*(owner: ForcedAudits, services: var Services,
    initial: var InitialAudits) =
  ## Release only fully published declarations after the graph lease has retired.
  if not owner.canExpire or not services.stateProofAvailable: return
  for row in 0..<initial.readyDeclarationCount:
    if owner.declaredProgress[row].selected >= initial.declarationAt(row).selected.count:
      initial.releaseDeclarationOrigin(services, row)
proc expireBefore*(owner: var ForcedAudits, streams: var NodeService, floor: uint64,
    declarations, pending: array[256, bool]) {.requires: owner.canExpire.} =
  ## Move progress in the same stable order as the underlying detached duty queues.
  var kept = 0
  for row in 0..<pending.len:
    # Negative retries follow the original live pending ordinal.
    if pending[row]:
      owner.completed[kept] = owner.completed[row]
      owner.retry[kept] = owner.retry[row]
      inc kept
  for row in kept..<pending.len:
    # Reused storage starts without completion or cooldown from a retired record.
    owner.completed[row] = false
    owner.retry[row] = default(MonoTime)
  kept = 0
  for row in 0..<declarations.len:
    # Completed CE144 reports retain their next report cursor.
    if declarations[row]:
      owner.declaredProgress[kept] = owner.declaredProgress[row]
      inc kept
  for row in kept..<declarations.len: owner.declaredProgress[row] = default(DeclaredProgress)
  owner.cursor = 0
  owner.declarationCursor = 0
  kept = 0
  for row in 0..<owner.refresh.len:
    # Expired original cohorts can never be routed by a later successor plan.
    if uint64(uint32(owner.refresh[row].record.judgmentRecord.epoch)) >= floor:
      if kept != row: owner.refresh[kept] = move(owner.refresh[row])
      inc kept
  owner.refresh.setLen(kept)
  owner.refreshCursor = 0
  owner.gossip.expireBefore(streams, floor)
func configured*(owner: ForcedAudits): bool =
  ## Local declarations require an enabled evaluation and publication pipeline.
  owner.policy.ready

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
  owner.declared = false
  owner.reportOrdinal = 0
  owner.source = default(AuditOriginId)
  owner.proof = default(ProofWorkerTicket)
  owner.plan = default(AuditParticipationPlan)
  owner.publication = default(AuditPublication)

proc finish(owner: var ForcedAudits, clock: MonoTime, complete: bool) =
  ## Keep unavailable work eligible after a bounded delay.
  if owner.declared:
    if complete: inc owner.declaredProgress[owner.declaration].selected
    else: owner.declaredProgress[owner.declaration].retry = clock+initDuration(seconds = 1)
  else:
    owner.completed[owner.row] = complete
    if complete: owner.releasable = owner.source
    owner.retry[owner.row] = clock+initDuration(seconds = 1)
  owner.clear()

proc rememberRoute(owner: var ForcedAudits, record: QualifiedJudgment,
    mode: JudgmentDeliveryMode, awaiting: bool): bool =
  ## Keep even an empty initial route so actual later successor rosters can receive the original signature.
  let raw = record.judgmentRecord
  let head = owner.plan.participationInfo.value.source
  for index in 0..<owner.refresh.len:
    # Opposite judgments remain distinct accountable records.
    let old = owner.refresh[index].record.judgmentRecord
    if uint32(old.epoch) != uint32(raw.epoch) or uint16(old.validator) != uint16(raw.validator) or
        old.valid != raw.valid or array[32, byte](old.report) != array[32, byte](
            raw.report): continue
    if owner.refresh[index].mode == JudgmentDeliveryMode.Produced and mode ==
        JudgmentDeliveryMode.Relayed:
      return true
    owner.refresh[index].mode = mode
    owner.refresh[index].head = head
    owner.refresh[index].awaiting = awaiting
    return true
  if owner.refresh.len >= 256: return false
  owner.refresh.add(RefreshRecord(record: record, basis: owner.plan.routingBasis,
      mode: mode, head: head, awaiting: awaiting))
  true
proc pollRefresh(owner: var ForcedAudits, services: var Services, clock: MonoTime) =
  ## Refresh uses the exact original obligation and does not acquire, evaluate or sign again.
  if services.stateProofActive(owner.proof):
    let outcome = services.collectAudit(owner.proof)
    if outcome.kind == ManagedAuditKind.Uninitialized: return
    if outcome.kind == ManagedAuditKind.ParticipationPlanned:
      let plan = outcome.participationPlan
      let row = owner.refreshing
      if owner.gossip.offer(owner.refresh[row].record, plan, owner.refresh[row].mode):
        owner.refresh[row].head = plan.participationInfo.value.source
        owner.refresh[row].awaiting = false
  owner.refresh[owner.refreshing].retry = clock+initDuration(seconds = 1)
  owner.clear()
proc startRefresh(owner: var ForcedAudits, services: var Services,
    clock: MonoTime): bool {.raises.} =
  ## Rotate through retained records whose checked topology stamp predates the trusted selected head.
  let count = owner.refresh.len
  if count == 0: return false
  let head = array[32, byte](services.auditRoutingHead)
  owner.refreshCursor = owner.refreshCursor mod count
  for turn in 0..<count:
    # A single failed topology capture does not prevent refreshing other obligations.
    let row = owner.refreshCursor
    owner.refreshCursor = (row+1) mod count
    if clock < owner.refresh[row].retry or
        (not owner.refresh[row].awaiting and array[32, byte](owner.refresh[row].head) == head):
      continue
    let started = services.beginAuditRoutingRefresh(owner.refresh[row].basis,
        owner.policy.participation)
    if started.error == StateProofAdmissionError.Busy: return false
    if started.error != StateProofAdmissionError.None:
      owner.refresh[row].retry = clock+initDuration(seconds = 1)
      return false
    owner.refreshing = row
    owner.proof = started.value
    owner.phase = Phase.Refreshing
    return true
  false
proc releaseCompleted(owner: var ForcedAudits, services: var Services,
    receipt: JudgmentDispatcher) =
  ## Wait until every relay sharing this exact source has settled and all graph leases have ended.
  if not owner.releasable.valid or not services.stateProofAvailable: return
  let source = owner.releasable
  owner.releasable = default(AuditOriginId)
  for row in 0..<receipt.pendingCount:
    # Any unfinished row can still need the private origin for its first plan.
    if not owner.completed[row] and receipt.pendingAt(row).originId == source: return
  discard services.releaseDisputedAudit(source)
proc alreadyJudged(owner: ForcedAudits, plan: AuditParticipationPlan): bool =
  ## A later negative signature can reuse completed local judgments for each actual original position.
  let info = plan.participationInfo.value
  for index in 0..<info.localValidators:
    # Only locally produced original signatures count, never another auditor's relay or a bare receipt.
    let validator = uint16(uint64(plan.localValidatorAt(index).value))
    var found = false
    for retained in owner.refresh:
      let record = retained.record.judgmentRecord
      let sameEpoch = uint64(uint32(record.epoch)) == info.epoch
      let sameOrdinal = uint16(record.validator) == validator
      let sameReport = array[32, byte](record.report) == array[32, byte](info.report)
      if retained.mode == JudgmentDeliveryMode.Produced and sameEpoch and sameOrdinal and sameReport:
        found = true
        break
    if not found: return false
  true
proc poll*(owner: var ForcedAudits, services: var Services, streams: var NodeService,
    receipt: var JudgmentDispatcher, acquisition: AuditAcquisition, clock: MonoTime) =
  ## Collect the exact managed worker generation before advancing the obligation.
  if not owner.policy.ready: return
  owner.releaseCompleted(services, receipt)
  owner.gossip.poll(streams, clock)
  case owner.phase
  of Phase.Refreshing: owner.pollRefresh(services, clock)
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
      if not owner.declared:
        let record = receipt.pendingAt(owner.row).judgment
        let queued = owner.gossip.offer(record, owner.plan, JudgmentDeliveryMode.Relayed)
        if not owner.rememberRoute(record, JudgmentDeliveryMode.Relayed, not queued):
          owner.finish(clock, false)
          return
        if owner.alreadyJudged(owner.plan):
          owner.finish(clock, true)
          return
        for row in 0..<receipt.pendingCount:
          # A distinct signed claim still relays, but a completed exact private origin needs no second execution.
          if owner.completed[row] and receipt.pendingAt(row).originId == owner.source:
            owner.finish(clock, true)
            return
      owner.phase = Phase.Acquire
    elif owner.phase == Phase.Signing and outcome.kind == ManagedAuditKind.PublicationPrepared:
      if outcome.publicationId != owner.source or outcome.publicationOrdinal != owner.reportOrdinal:
        owner.finish(clock, false)
        return
      owner.publication = outcome.preparedPublication
      owner.publishDeadline = clock+initDuration(seconds = 1)
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
    if clock >= owner.publishDeadline:
      owner.finish(clock, false)
      return
    if not receipt.rememberPublication(owner.publication): return
    let record = qualifyLocalJudgment(owner.publication.signedJudgment).value
    let queued = owner.gossip.offer(record, owner.plan, JudgmentDeliveryMode.Produced)
    if not owner.rememberRoute(record, JudgmentDeliveryMode.Produced, not queued): return
    owner.publication = default(AuditPublication)
    inc owner.validator
    if owner.declared or owner.validator == owner.plan.participationInfo.value.localValidators:
      owner.finish(clock, true)
    else:
      owner.phase = Phase.Sign
  else: discard

proc startDeclared(owner: var ForcedAudits, services: var Services, streams: NodeService,
    initial: InitialAudits, clock: MonoTime): bool {.raises.} =
  ## A published declaration selects only its original core-derived report and signing position.
  let count = initial.readyDeclarationCount
  if count == 0: return false
  owner.declarationCursor = owner.declarationCursor mod count
  for turn in 0..<count:
    # A missing report cannot prevent another declared duty from advancing.
    let row = owner.declarationCursor
    owner.declarationCursor = (row+1) mod count
    let entry = initial.declarationAt(row)
    let progress = owner.declaredProgress[row]
    if clock < progress.retry or progress.selected >= entry.selected.count: continue
    let ordinal = entry.reportOrdinals[progress.selected]
    let started = services.beginAuditParticipation(entry.origin, ordinal,
        streams.localIdentity, owner.policy.participation)
    if started.error == StateProofAdmissionError.Busy: return false
    if started.error != StateProofAdmissionError.None:
      owner.declaredProgress[row].retry = clock+initDuration(seconds = 1)
      return false
    owner.source = entry.origin
    owner.declared = true
    owner.declaration = row
    owner.reportOrdinal = ordinal
    owner.originalValidator = StateValidatorIndex(uint64(uint16(entry.record.validator)))
    owner.proof = started.value
    owner.phase = Phase.Planning
    return true
  false

proc submit*(owner: var ForcedAudits, services: var Services, streams: NodeService,
    receipt: JudgmentDispatcher, acquisition: var AuditAcquisition, initial: InitialAudits,
        clock: MonoTime): bool {.raises.} =
  ## Admit one operation per foreground arbitration turn.
  if not owner.policy.ready or not services.stateProofAvailable: return false
  owner.releaseCompleted(services, receipt)
  case owner.phase
  of Phase.Idle:
    let refreshFirst = owner.preferRefresh
    owner.preferRefresh = not refreshFirst
    if refreshFirst and owner.startRefresh(services, clock): return true
    let declaredFirst = owner.preferDeclared
    owner.preferDeclared = not declaredFirst
    if declaredFirst and owner.startDeclared(services, streams, initial, clock): return true
    let count = receipt.pendingCount
    if count > 0: owner.cursor = owner.cursor mod count
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
    if not declaredFirst and owner.startDeclared(services, streams, initial, clock): return true
    if not refreshFirst: return owner.startRefresh(services, clock)
  of Phase.Acquire:
    if acquisition.begin(owner.policy.acquisition, owner.source, owner.reportOrdinal, clock):
      owner.phase = Phase.Acquiring
      return true
  of Phase.Sign:
    let index = if owner.declared: owner.originalValidator
      else: owner.plan.localValidatorAt(owner.validator).value
    let started = services.beginAuditPublication(owner.source, owner.reportOrdinal, index,
        owner.policy.publication)
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
  if owner.phase in {Phase.Planning, Phase.Signing, Phase.Refreshing} and services.stateProofActive(owner.proof):
    if services.cancelStateProof(owner.proof): services.stopStateProofs()
  owner.gossip.close(streams)
  owner.clear()
  owner.policy = default(ForcedAuditPolicy)
  owner.cursor = 0
  owner.completed = default(array[256, bool])
  owner.retry = default(array[256, MonoTime])
  owner.declaration = 0
  owner.declarationCursor = 0
  owner.declaredProgress = default(array[256, DeclaredProgress])
  owner.preferDeclared = false
  owner.releasable = default(AuditOriginId)
  owner.refresh = @[]
  owner.refreshCursor = 0
  owner.refreshing = 0
  owner.preferRefresh = false
