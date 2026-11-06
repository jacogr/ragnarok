# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bounded private registry owns complete audit origins and actual evaluations. Services alone admits origins against its canonical trust and accesses this registry only after every shared source lease retires.
import ./[audit_origin, audit_context, audit_evaluation]
import ../chain/parameters
import ../codec/bounded
import ../codec/state/trie

type
  AuditRegistryLimits* = object ## Aggregate whole-state and detached-context ceilings count repeated snapshot pins conservatively even when immutable subtrees share storage.
    blocks*, entries*: ElementLimit
    nodes*: TrieNodeLimit
    valueBytes*, contextBytes*: ByteLimit
  RegistryIdentity = ref object ## Host-only immutable namespace never enters a worker source graph or points back to this registry.
    marker: uint8
  AuditOriginId* = object ## Private namespace and nonwrapping serial reject foreign, stale and fabricated origin selectors.
    owner: nil RegistryIdentity
    serial: uint64
  EvaluationSlot = object ## Mutable slots stay under the Services graph gate; host observers receive copied metadata only.
    completed: bool
    evaluation: AuditEvaluation
    info: AuditEvaluationInfo
  OriginRow = object ## Acyclic owners share one genuine complete predecessor among the block's original report targets.
    id: AuditOriginId
    origin: AuditBlockOrigin
    dispute: AuditDisputeOrigin
    info: AuditOriginInfo
    contextBytes, epoch: uint64
    slots: seq[EvaluationSlot]
  AuditOriginRegistry* = object ## Not a concurrent container: all source-bearing getters, mutation and destruction require the owning Services graph lease to be idle or joined.
    identity: nil RegistryIdentity
    limits: AuditRegistryLimits
    next, entries, nodes, values, contexts, minimumEpoch: uint64
    rows: seq[OriginRow]
  AuditRegistryError* {.pure.} = enum ## No failure exposes a source or partially installed evaluation.
    Uninitialized, None, Unconfigured, InvalidSource, InvalidId, InvalidIndex,
    NotEvaluated, LimitExceeded, Exhausted, SourceConflict, Expired
  AuditRegistryResult*[T] = object ## Defaults/refusals have only a reason; complete success alone carries its selected capability or metadata.
    case status: AuditRegistryError
    of None: completed: T
    else: discard # No accepted origin, evaluation or prior prefix exists on failure.
func error*[T](outcome: AuditRegistryResult[T]): AuditRegistryError =
  ## Observe the selected reason before extracting source-bearing success.
  outcome.status
func value*[T](outcome: AuditRegistryResult[T]): T {.requires: outcome.status ==
    AuditRegistryError.None.} =
  ## The owning Services actor must keep all returned aliases frozen through native collection or joined shutdown.
  outcome.completed
func auditRegistryFailure*[T](reason: AuditRegistryError): AuditRegistryResult[
    T] {.requires: reason != AuditRegistryError.None.} =
  ## Compose a typed boundary refusal without granting any source-bearing success payload.
  AuditRegistryResult[T](status: reason)
func valid*(limits: AuditRegistryLimits): bool =
  ## Defaults retain nothing; finite independent totals cover complete maps and per-report/context metadata.
  uint64(limits.blocks) in 1'u64..64'u64 and uint64(limits.entries) in 1'u64..64000000'u64 and
    uint64(limits.nodes) > 0 and uint64(limits.nodes) <= 256'u64*1024*1024 and
    uint64(limits.valueBytes) > 0 and uint64(limits.valueBytes) <= 64'u64*1024*1024*1024 and
    uint64(limits.contextBytes) > 0 and uint64(limits.contextBytes) <= 512'u64*1024*1024
func valid*(id: AuditOriginId): bool =
  ## A default selector identifies no registered source in any lifetime.
  id.owner != nil and id.serial != 0
func `==`*(left, right: AuditOriginId): bool =
  ## Equality compares namespace and serial; even equal default selectors remain invalid for every registry lookup.
  left.owner == right.owner and left.serial == right.serial
func len*(registry: AuditOriginRegistry): int =
  ## Scalar occupancy reads no full-state or evaluation child.
  registry.rows.len
func configured*(registry: AuditOriginRegistry): bool =
  ## Optional registry activation never follows from default capacity fields.
  registry.identity != nil
proc configure*(registry: var AuditOriginRegistry, limits: AuditRegistryLimits): bool =
  ## A live namespace cannot be reconfigured over retained obligations or silently reset its serial.
  if registry.configured or not limits.valid or sizeof(OriginRow) > 1024 or sizeof(EvaluationSlot) >
      512: return false
  registry.identity = RegistryIdentity(marker: 1)
  registry.limits = limits
  registry.next = 0
  true
proc find(registry: AuditOriginRegistry, id: AuditOriginId): int =
  ## Private exact identity matching never accepts another registry's serial1 or a previous cleared lifetime.
  if not id.valid or registry.identity != id.owner: return -1
  for ordinal in 0..<registry.rows.len:
    if registry.rows[ordinal].id.serial == id.serial: return ordinal
  -1
proc uncharge(registry: var AuditOriginRegistry, ordinal: int) =
  ## Release exactly the original row reservation before its owner retires.
  let row = registry.rows[ordinal]
  if row.dispute.valid:
    let info = row.dispute.disputeInfo.value
    registry.entries -= uint64(info.entries)
    registry.nodes -= info.nodes
    registry.values -= info.valueBytes
  else:
    registry.entries -= uint64(row.info.entries)
    registry.nodes -= row.info.nodes
    registry.values -= row.info.valueBytes
  registry.contexts -= row.contextBytes
proc releaseDispute*(registry: var AuditOriginRegistry, id: AuditOriginId): bool =
  ## Only a disputed-only source may retire independently of the epoch's declared block duties.
  let index = registry.find(id)
  if index < 0 or not registry.rows[index].dispute.valid: return false
  registry.uncharge(index)
  for ordinal in index..<registry.rows.len-1:
    # Existing exact selectors continue resolving after stable compaction.
    registry.rows[ordinal] = move(registry.rows[ordinal+1])
  registry.rows.setLen(registry.rows.len-1)
  true
proc expireBefore*(registry: var AuditOriginRegistry, minimumEpoch: uint64) =
  ## Retire previous obligations only under the owning graph gate and never reopen a retired epoch.
  if minimumEpoch <= registry.minimumEpoch: return
  registry.minimumEpoch = minimumEpoch
  var kept = 0
  for ordinal in 0..<registry.rows.len:
    # Stable compaction preserves every live origin ID and never resets the serial.
    if registry.rows[ordinal].epoch >= minimumEpoch:
      if kept != ordinal: registry.rows[kept] = move(registry.rows[ordinal])
      inc kept
    else:
      registry.uncharge(ordinal)
  registry.rows.setLen(kept)
proc retain*(registry: var AuditOriginRegistry, origin: AuditBlockOrigin): AuditRegistryResult[
    AuditOriginId] =
  ## Services first checks independent canonical/checkpoint trust. Whole additional logical metrics and report slots are reserved before this registry mutates.
  if not registry.configured: return AuditRegistryResult[AuditOriginId](
      status: AuditRegistryError.Unconfigured)
  if not origin.valid: return AuditRegistryResult[AuditOriginId](
      status: AuditRegistryError.InvalidSource)
  let info = origin.originInfo.value
  let context = origin.originContext.value.contextInfo.value
  if context.epoch < registry.minimumEpoch:
    return auditRegistryFailure[AuditOriginId](AuditRegistryError.Expired)
  for ordinal in 0..<registry.rows.len:
    # Repeated genuine captures return the existing immutable source, never overwrite a differently rooted or parameterized obligation.
    if registry.rows[ordinal].dispute.valid: continue # Disputed-only reports have no available-block identity.
    let old = registry.rows[ordinal].info
    if array[32, byte](old.blockHash) == array[32, byte](info.blockHash):
      let prior = registry.rows[ordinal].origin
      let facts = prior.originContext.value.contextInfo.value
      if array[32, byte](facts.blockRoot) != array[32, byte](context.blockRoot) or
          array[32, byte](old.parentRoot) != array[32, byte](info.parentRoot) or
          facts.bodyDigest != context.bodyDigest or
              not prior.originParameters.value.sameParameterProfile(origin.originParameters.value):
        return AuditRegistryResult[AuditOriginId](status: AuditRegistryError.SourceConflict)
      return AuditRegistryResult[AuditOriginId](status: AuditRegistryError.None,
          completed: registry.rows[ordinal].id)
  if registry.next == high(uint64): return AuditRegistryResult[AuditOriginId](
      status: AuditRegistryError.Exhausted)
  let contextBytes = context.retainedBytes+uint64(
      info.reports)*512+1024 # A validated context has at most341 reports and64MiB source-free storage; this also reserves fixed rows and evaluation slots.
  if uint64(registry.rows.len) >= uint64(registry.limits.blocks) or
      uint64(info.entries) > uint64(registry.limits.entries)-registry.entries or
      info.nodes > uint64(registry.limits.nodes)-registry.nodes or
      info.valueBytes > uint64(registry.limits.valueBytes)-registry.values or
      contextBytes > uint64(registry.limits.contextBytes)-registry.contexts:
    return AuditRegistryResult[AuditOriginId](status: AuditRegistryError.LimitExceeded)
  inc registry.next
  let id = AuditOriginId(owner: registry.identity, serial: registry.next)
  registry.rows.add(OriginRow(id: id, origin: origin, dispute: default(AuditDisputeOrigin),
      info: info, contextBytes: contextBytes, epoch: context.epoch,
    slots: newSeq[EvaluationSlot](info.reports)))
  registry.entries += uint64(info.entries)
  registry.nodes += info.nodes
  registry.values += info.valueBytes
  registry.contexts += contextBytes
  AuditRegistryResult[AuditOriginId](status: AuditRegistryError.None, completed: id)
proc sameDispute(left, right: AuditDisputeOrigin): bool =
  ## Equal report names alone cannot replace the original auditor cohort or whole profile. Once independently trusted, the first genuine complete historical source remains pinned across benign receipt/support/head changes.
  if not left.valid or not right.valid: return false
  let a = left.disputeInfo.value
  let b = right.disputeInfo.value
  array[32, byte](a.reportHash) == array[32, byte](b.reportHash) and a.epoch == b.epoch and
    array[32, byte](a.auditorHash) == array[32, byte](b.auditorHash) and
    left.reportAt(0).value.originParameters.value.sameParameterProfile(right.reportAt(
        0).value.originParameters.value)
proc retainDisputes*(registry: var AuditOriginRegistry,
    origins: openArray[AuditDisputeOrigin]): AuditRegistryResult[seq[AuditOriginId]] =
  ## Services independently binds every origin first. Complete-message logical reservations and duplicate planning precede the first mutation; no late refusal retains an accepted prefix.
  if not registry.configured: return auditRegistryFailure[seq[AuditOriginId]](
      AuditRegistryError.Unconfigured)
  if origins.len > 16: return auditRegistryFailure[seq[AuditOriginId]](
      AuditRegistryError.LimitExceeded)
  var planned = newSeq[int](origins.len)
  var additions: seq[AuditDisputeOrigin] = @[]
  var entries = registry.entries
  var nodes = registry.nodes
  var values = registry.values
  var contexts = registry.contexts
  for ordinal in 0..<origins.len:
    # Bounded pairwise equality retains the first actual physical owner, so later evaluation and signing select that same registered target.
    let origin = origins[ordinal]
    if not origin.valid: return auditRegistryFailure[seq[AuditOriginId]](
        AuditRegistryError.InvalidSource)
    let info = origin.disputeInfo.value
    if info.epoch < registry.minimumEpoch:
      return auditRegistryFailure[seq[AuditOriginId]](AuditRegistryError.Expired)
    var existing = -1
    for row in 0..<registry.rows.len:
      if sameDispute(registry.rows[row].dispute, origin): existing = row
    if existing >= 0:
      planned[ordinal] = existing
      continue
    var repeated = -1
    for row in 0..<additions.len:
      if sameDispute(additions[row], origin): repeated = row
    if repeated >= 0:
      planned[ordinal] = registry.rows.len+repeated
      continue
    if info.retainedBytes > high(uint64)-1536:
      return auditRegistryFailure[seq[AuditOriginId]](AuditRegistryError.LimitExceeded)
    let contextBytes = info.retainedBytes+1536
    if uint64(registry.rows.len+additions.len) >= uint64(registry.limits.blocks) or
        uint64(info.entries) > uint64(registry.limits.entries)-entries or
        info.nodes > uint64(registry.limits.nodes)-nodes or
        info.valueBytes > uint64(registry.limits.valueBytes)-values or
        contextBytes > uint64(registry.limits.contextBytes)-contexts:
      return auditRegistryFailure[seq[AuditOriginId]](AuditRegistryError.LimitExceeded)
    entries += uint64(info.entries)
    nodes += info.nodes
    values += info.valueBytes
    contexts += contextBytes
    planned[ordinal] = registry.rows.len+additions.len
    additions.add(origin)
  if uint64(additions.len) > high(uint64)-registry.next:
    return auditRegistryFailure[seq[AuditOriginId]](AuditRegistryError.Exhausted)
  for origin in additions:
    # All logical capacity and nonwrapping serials have been reserved. Installation has no protocol/resource refusal branch.
    inc registry.next
    let id = AuditOriginId(owner: registry.identity, serial: registry.next)
    registry.rows.add(OriginRow(id: id, origin: default(AuditBlockOrigin), dispute: origin,
      info: default(AuditOriginInfo), contextBytes: origin.disputeInfo.value.retainedBytes+1536,
      epoch: origin.disputeInfo.value.epoch,
      slots: newSeq[EvaluationSlot](1)))
  registry.entries = entries
  registry.nodes = nodes
  registry.values = values
  registry.contexts = contexts
  var ids = newSeq[AuditOriginId](origins.len)
  for ordinal in 0..<ids.len:
    # Host-only selectors contain no full-state graph and preserve input order, including duplicate rows.
    ids[ordinal] = registry.rows[planned[ordinal]].id
  AuditRegistryResult[seq[AuditOriginId]](status: AuditRegistryError.None, completed: move(ids))
proc target*(registry: AuditOriginRegistry, id: AuditOriginId,
    ordinal: int): AuditRegistryResult[AuditReportOrigin] =
  ## One guarded selector resolves either genuine source form without constructing an availability block for a disputed-only report.
  let found = registry.find(id)
  if found < 0: return auditRegistryFailure[AuditReportOrigin](AuditRegistryError.InvalidId)
  if ordinal < 0 or ordinal >= registry.rows[found].slots.len:
    return auditRegistryFailure[AuditReportOrigin](AuditRegistryError.InvalidIndex)
  let row = registry.rows[found]
  let selected = if row.dispute.valid: row.dispute.reportAt(ordinal) else: row.origin.reportAt(ordinal)
  if selected.error != AuditOriginError.None:
    return auditRegistryFailure[AuditReportOrigin](AuditRegistryError.InvalidSource)
  AuditRegistryResult[AuditReportOrigin](status: AuditRegistryError.None, completed: selected.value)
proc origin*(registry: AuditOriginRegistry, id: AuditOriginId): AuditRegistryResult[
    AuditBlockOrigin] =
  ## Source-bearing lookup is used only while the owning Services graph is exclusively accessible.
  let found = registry.find(id)
  if found < 0: return AuditRegistryResult[AuditBlockOrigin](status: AuditRegistryError.InvalidId)
  if registry.rows[found].dispute.valid:
    return auditRegistryFailure[AuditBlockOrigin](AuditRegistryError.InvalidSource)
  AuditRegistryResult[AuditBlockOrigin](status: AuditRegistryError.None, completed: registry.rows[found].origin)
proc rememberEvaluation*(registry: var AuditOriginRegistry, id: AuditOriginId, ordinal: int,
    evaluation: AuditEvaluation): AuditRegistryResult[bool] =
  ## Only actual evaluation of this exact registered private target can populate a slot; public booleans and equal-root replacement origins are insufficient.
  let found = registry.find(id)
  if found < 0: return AuditRegistryResult[bool](status: AuditRegistryError.InvalidId)
  if ordinal < 0 or ordinal >= registry.rows[found].slots.len:
    return AuditRegistryResult[bool](status: AuditRegistryError.InvalidIndex)
  let target = registry.target(id, ordinal).value
  if not evaluation.valid or not evaluation.matchesOrigin(target):
    return AuditRegistryResult[bool](status: AuditRegistryError.SourceConflict)
  let info = evaluation.evaluationInfo.value
  if registry.rows[found].slots[ordinal].completed:
    # A retry may confirm the same judgment, but a contradictory result can never silently replace previously retained evidence.
    let old = registry.rows[found].slots[ordinal].info
    if old.positive != info.positive or array[32, byte](old.reportHash) != array[32, byte](
        info.reportHash):
      return AuditRegistryResult[bool](status: AuditRegistryError.SourceConflict)
    return AuditRegistryResult[bool](status: AuditRegistryError.None, completed: false)
  registry.rows[found].slots[ordinal] = EvaluationSlot(completed: true, evaluation: evaluation, info: info)
  AuditRegistryResult[bool](status: AuditRegistryError.None, completed: true)
proc evaluation*(registry: AuditOriginRegistry, id: AuditOriginId,
    ordinal: int): AuditRegistryResult[AuditEvaluation] =
  ## The leased signer receives the private completed capability; host controllers must use detached evaluationInfo instead.
  let found = registry.find(id)
  if found < 0: return AuditRegistryResult[AuditEvaluation](status: AuditRegistryError.InvalidId)
  if ordinal < 0 or ordinal >= registry.rows[found].slots.len:
    return AuditRegistryResult[AuditEvaluation](status: AuditRegistryError.InvalidIndex)
  if not registry.rows[found].slots[ordinal].completed:
    return AuditRegistryResult[AuditEvaluation](status: AuditRegistryError.NotEvaluated)
  AuditRegistryResult[AuditEvaluation](status: AuditRegistryError.None, completed: registry.rows[
      found].slots[ordinal].evaluation)
proc evaluationInfo*(registry: AuditOriginRegistry, id: AuditOriginId,
    ordinal: int): AuditRegistryResult[AuditEvaluationInfo] =
  ## Copy cached fixed metadata only after the owner opens its graph gate; no full source alias escapes to a controller.
  let found = registry.find(id)
  if found < 0: return AuditRegistryResult[AuditEvaluationInfo](
      status: AuditRegistryError.InvalidId)
  if ordinal < 0 or ordinal >= registry.rows[found].slots.len:
    return AuditRegistryResult[AuditEvaluationInfo](status: AuditRegistryError.InvalidIndex)
  if not registry.rows[found].slots[ordinal].completed:
    return AuditRegistryResult[AuditEvaluationInfo](status: AuditRegistryError.NotEvaluated)
  AuditRegistryResult[AuditEvaluationInfo](status: AuditRegistryError.None,
      completed: registry.rows[found].slots[ordinal].info)
proc clear*(registry: var AuditOriginRegistry) =
  ## Explicit Services shutdown joins every shared borrower before releasing private state/key/evaluation aliases and invalidating all old selectors.
  registry.rows = @[]
  registry.identity = nil
  registry.limits = default(AuditRegistryLimits)
  registry.next = 0
  registry.minimumEpoch = 0
  registry.entries = 0
  registry.nodes = 0
  registry.values = 0
  registry.contexts = 0
