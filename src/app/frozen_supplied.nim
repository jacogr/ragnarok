# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze unqualified complete declarations under whole-copy quotas, bound to one actual collected supplied target.
import ./chain
import ./collected/supplied/[plan as collected_supplied_plan, state as collected_supplied_state]
import ../state/current/logical as current_logical
import ../state/supplied/services as supplied_services
import ../state/accumulation/current/update as accumulation_current_update
import ../codec/bounded
import ../codec/state/composition as state_composition
type
  FrozenSuppliedInfo* = object ## Exact copied descriptor/payload accounting grants no matching or execution authority.
    services*: int
    facts*, bytes*: uint64
  FrozenSuppliedData = ref object ## Immutable copied declarations and original target form an acyclic owner.
    plan: CollectedSuppliedPlan
    rows: seq[StateService]
    info: FrozenSuppliedInfo
  FrozenSuppliedInput* = object ## No unchecked raw arrays or replacement target can enter later qualification.
    data: nil FrozenSuppliedData
  FrozenSuppliedError* {.pure.} = enum ## Admission, stale target and genuine complete matching failure remain distinct.
    Uninitialized, None, InvalidPlan, StaleUpdate, LimitExceeded, OpaqueValues, QualificationFailure
  FrozenSuppliedResult*[T] = object ## Failed capture/execution exposes no frozen or qualified prefix.
    case status: FrozenSuppliedError
    of None: completed: T
    of QualificationFailure: qualificationReason: CollectedSuppliedResult
    else: discard # Defaults and refused copies retain no target or partial declaration authority.
func error*[T](outcome: FrozenSuppliedResult[T]): FrozenSuppliedError =
  ## Observe immutable selected stages only.
  outcome.status
func value*[T](outcome: FrozenSuppliedResult[T]): T {.inline, requires: outcome.status ==
    FrozenSuppliedError.None.} =
  ## Extract only a completely frozen or genuinely qualified result.
  outcome.completed
func qualificationFailure*[T](outcome: FrozenSuppliedResult[T]): CollectedSuppliedResult {.inline,
    requires: outcome.status == FrozenSuppliedError.QualificationFailure.} =
  ## Preserve actual complete-state and independently bounded logical matching causes.
  outcome.qualificationReason
proc freezeCollectedSupplied*(chain: ApplicationChain, plan: CollectedSuppliedPlan,
    rows: openArray[StateService], limits: SuppliedServicesLimits): FrozenSuppliedResult[
        FrozenSuppliedInput] =
  ## Stable borrowed input is admitted wholly before any raw key, payload or descriptor copy; it remains unqualified supplied evidence.
  let target = plan.collectedSuppliedUpdate
  if target.error != CollectedSuppliedPlanError.None:
    return FrozenSuppliedResult[FrozenSuppliedInput](status: FrozenSuppliedError.InvalidPlan)
  if not chain.canInstallPrepared(target.value):
    return FrozenSuppliedResult[FrozenSuppliedInput](status: FrozenSuppliedError.StaleUpdate)
  template refuse() =
    return FrozenSuppliedResult[FrozenSuppliedInput](status: FrozenSuppliedError.LimitExceeded)
  if uint64(rows.len) > uint64(limits.services): refuse()
  var bytes = min(uint64(limits.bytes), uint64(high(int)))
  let admitted = bytes
  var facts = uint64(limits.facts)
  template charge(count: int, kind: untyped) =
    block:
      let amount = uint64(count)
      if amount > facts or amount > bytes div uint64(sizeof(kind)): refuse()
      facts -= amount
      bytes -= amount * uint64(sizeof(kind)) # Division proves multiplication and every later native array allocation.
  template payload(count: int) =
    block:
      let amount = uint64(count)
      if amount > uint64(limits.perValue) or amount > bytes: refuse()
      bytes -= amount # Whole-source subtraction bounds all raw keys and copied values, including present-empty bytes.
  charge(rows.len, StateService)
  for row in rows:
    if row.captured.len != 0:
      return FrozenSuppliedResult[FrozenSuppliedInput](
          status: FrozenSuppliedError.OpaqueValues) # Opaque physical values cannot become complete logical declarations.
    charge(row.storage.len, StateStorageItem)
    charge(row.preimages.len, StatePreimageItem)
    charge(row.requests.len, StateRequestItem)
    for item in row.storage:
      payload(item.key.len)
      payload(item.value.len)
    for item in row.preimages: payload(item.value.len)
  var owned = newSeq[StateService](rows.len)
  for i, row in rows:
    owned[i] = StateService(service: row.service, metadata: row.metadata,
      storage: newSeq[StateStorageItem](row.storage.len), preimages: newSeq[StatePreimageItem](
          row.preimages.len),
      requests: newSeq[StateRequestItem](row.requests.len))
    for j, item in row.storage:
      owned[i].storage[j].key = newSeq[byte](item.key.len)
      owned[i].storage[j].value = newSeq[byte](item.value.len)
      for k, octet in item.key: owned[i].storage[j].key[k] = octet
      for k, octet in item.value: owned[i].storage[j].value[k] = octet
    for j, item in row.preimages:
      owned[i].preimages[j].hash = item.hash
      owned[i].preimages[j].value = newSeq[byte](item.value.len)
      for k, octet in item.value: owned[i].preimages[j].value[k] = octet
    for j, item in row.requests: owned[i].requests[
        j] = item # Tagged histories are fixed values, not borrowed arrays.
  FrozenSuppliedResult[FrozenSuppliedInput](status: FrozenSuppliedError.None,
    completed: FrozenSuppliedInput(data: FrozenSuppliedData(plan: plan, rows: owned,
      info: FrozenSuppliedInfo(services: rows.len, facts: uint64(limits.facts)-facts,
          bytes: admitted-bytes))))
proc frozenSuppliedInfo*(source: FrozenSuppliedInput): FrozenSuppliedResult[FrozenSuppliedInfo] =
  ## Observe copied accounting without exposing mutable backing declarations.
  let data = source.data
  if data == nil: return FrozenSuppliedResult[FrozenSuppliedInfo](
      status: FrozenSuppliedError.InvalidPlan)
  FrozenSuppliedResult[FrozenSuppliedInfo](status: FrozenSuppliedError.None, completed: data.info)
proc executeFrozenSupplied*(chain: ApplicationChain,
    source: FrozenSuppliedInput): FrozenSuppliedResult[CurrentLogicalState] =
  ## Recheck the exact canonical prior, then qualify only this privately frozen target/input/policy combination.
  let data = source.data
  if data == nil: return FrozenSuppliedResult[CurrentLogicalState](
      status: FrozenSuppliedError.InvalidPlan)
  if not chain.canInstallPrepared(data.plan.collectedSuppliedUpdate.value):
    return FrozenSuppliedResult[CurrentLogicalState](status: FrozenSuppliedError.StaleUpdate)
  let qualified = executeCollectedSupplied(chain, data.plan, data.rows)
  if qualified.error != CollectedSuppliedError.None:
    return FrozenSuppliedResult[CurrentLogicalState](
        status: FrozenSuppliedError.QualificationFailure, qualificationReason: qualified)
  FrozenSuppliedResult[CurrentLogicalState](status: FrozenSuppliedError.None,
      completed: qualified.value)
