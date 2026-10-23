# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen bounded actual-successor service reconstruction, preserving original logical identities and raw keys.
## Planning copies no payload and hashes nothing; mutable output declarations and full current qualification are later stages.
import ./[current_request_keys, current_identities, supplied_logical_inventory, supplied_services,
    inventory, store, accumulation_current_update]
import ../codec/[bounded, state_layout, state_accounts, state_composition]
type
  CurrentRefreshLimits* = object ## Native service/child descriptors, raw/payload extents, bounded lookups and temporary codec wires are separate policies.
    projection*: SuppliedServicesLimits
    checks*: ElementLimit
    wireBytes*: ByteLimit
  CurrentRefreshInfo* = object ## Exact copied work/copy accounting cannot replace actual sources or frozen quotas.
    services*: int
    facts*, checks*, bytes*, wireBytes*, rawKeyBytes*, storageBytes*, preimageBytes*,
      requests*: uint64
  CurrentRefreshRefusal* {.pure.} = enum ## Resource refusals identify actual planning, projection or temporary wire admission.
    Planning, Projection, Wire
  CurrentRefreshPlan* = object ## Fixed policies retain one immutable request-key/original/genuine-update graph without target substitution.
    initialized: bool
    source: CurrentRequestKeys
    limits: CurrentRefreshLimits
    info: CurrentRefreshInfo
  CurrentRefreshPlanError* {.pure.} = enum ## Bad original provenance, missing actual values, malformed schema extents and resource policy stay distinct.
    Uninitialized, None, InvalidSource, MissingValue, MetadataExtent, RequestExtent, LimitExceeded
  CurrentRefreshPlanResult*[T] = object ## Failed/default alternatives grant no executable prefix or fabricated copy observations.
    case status: CurrentRefreshPlanError
    of None:
      completed: T
    of LimitExceeded:
      phase: CurrentRefreshRefusal
    else:
      discard # Every successful plan requires complete whole-output admission.
func error*[T](outcome: CurrentRefreshPlanResult[T]): CurrentRefreshPlanError =
  ## Inspect immutable selected stage only.
  outcome.status
func value*[T](outcome: CurrentRefreshPlanResult[T]): T {.inline, requires: outcome.status ==
    CurrentRefreshPlanError.None.} =
  ## Only whole successful plans expose original sources, quotas or copied accounting.
  outcome.completed
func refusedPhase*[T](outcome: CurrentRefreshPlanResult[T]): CurrentRefreshRefusal {.inline,
    requires: outcome.status == CurrentRefreshPlanError.LimitExceeded.} =
  ## Only an actual resource refusal names its failed policy boundary.
  outcome.phase
proc planCurrentRefresh*(source: CurrentRequestKeys,
    limits: CurrentRefreshLimits): CurrentRefreshPlanResult[CurrentRefreshPlan] =
  ## Inspect fixed original facts and actual successor cached value extents; all output/temporary bytes precede allocation, copying and decoding.
  template fail(reason: CurrentRefreshPlanError) =
    return CurrentRefreshPlanResult[CurrentRefreshPlan](status: reason)
  template refuse(boundary: CurrentRefreshRefusal) =
    return CurrentRefreshPlanResult[CurrentRefreshPlan](
        status: CurrentRefreshPlanError.LimitExceeded, phase: boundary)
  let binding = source.requestKeysSource
  if binding.error != CurrentRequestKeyError.None: fail(CurrentRefreshPlanError.InvalidSource)
  let original = binding.value.identityLogical.value
  let inventory = original.suppliedInventory.value
  let target = binding.value.identityUpdate.value.currentUpdateState
  let count = inventory.inventoryInfo.value.services
  if uint64(count) > uint64(limits.projection.services): refuse(CurrentRefreshRefusal.Projection)
  var available = min(uint64(limits.projection.bytes), uint64(high(int)))
  let budget = available
  var wire = min(uint64(limits.wireBytes), uint64(high(int)))
  let wireBudget = wire
  var facts = uint64(limits.projection.facts)
  var checks = uint64(limits.checks)
  var info = CurrentRefreshInfo(services: count, facts: 0, checks: 0, bytes: 0, wireBytes: 0,
      rawKeyBytes: 0, storageBytes: 0, preimageBytes: 0, requests: 0)
  template charge(count: int, kind: untyped) =
    block:
      let amount = uint64(count)
      if amount > facts or amount > available div uint64(sizeof(kind)): refuse(
          CurrentRefreshRefusal.Projection)
      facts-=amount
      available-=amount*uint64(sizeof(kind)) # Division proves native descriptor multiplication and addressing.
      if amount > checks: refuse(CurrentRefreshRefusal.Planning)
      checks-=amount
  template payload(extent: uint64) =
    block:
      let amount = extent
      if amount > uint64(limits.projection.perValue) or amount > available: refuse(
          CurrentRefreshRefusal.Projection)
      available-=amount # Whole output subtraction bounds raw keys and actual payload copies, including present-empty values.
  template wireCharge(extent: uint64) =
    block:
      let amount = extent
      if amount > wire: refuse(CurrentRefreshRefusal.Wire)
      wire-=amount # Exact temporary metadata/history bytes are admitted independently of application payload policy.
  charge(count, StateService)
  for i in 0..<count:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(ordinal).value
    charge(row.storage, StateStorageItem)
    charge(row.preimages, StatePreimageItem)
    charge(row.requests, StateRequestItem)
    let metadata = target.lookup(chapterServiceKey(StateChapter(255), row.service))
    if metadata.error != StateStoreError.None: fail(CurrentRefreshPlanError.MissingValue)
    if metadata.value.byteLength != ServiceMetadataBytes: fail(
        CurrentRefreshPlanError.MetadataExtent)
    wireCharge(uint64(ServiceMetadataBytes))
    for j in 0..<row.storage:
      let fact = inventory.inventoryStorageAt(ordinal, InventoryStorageIndex(uint64(j))).value
      let value = target.lookup(fact.key)
      if value.error != StateStoreError.None: fail(CurrentRefreshPlanError.MissingValue)
      payload(fact.keyBytes)
      let extent = uint64(value.value.byteLength)
      payload(extent)
      info.rawKeyBytes+=fact.keyBytes
      info.storageBytes+=extent # Sums cannot exceed admitted projection bytes, itself at most high(int).
    for j in 0..<row.preimages:
      let fact = inventory.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      let value = target.lookup(fact.key)
      if value.error != StateStoreError.None: fail(CurrentRefreshPlanError.MissingValue)
      let extent = uint64(value.value.byteLength)
      payload(extent)
      info.preimageBytes+=extent
    for j in 0..<row.requests:
      let key = source.currentRequestKeyAt(ordinal, InventoryRequestIndex(uint64(j))).value
      let value = target.lookup(key)
      if value.error != StateStoreError.None: fail(CurrentRefreshPlanError.MissingValue)
      let extent = uint64(value.value.byteLength)
      if extent > 13: fail(CurrentRefreshPlanError.RequestExtent) # Tagged request schema never exceeds three E4 slots plus count.
      wireCharge(extent)
    info.requests+=uint64(row.requests) # All request descriptors already fit the admitted fact count.
  info.facts = uint64(limits.projection.facts)-facts
  info.checks = uint64(limits.checks)-checks
  info.bytes = budget-available
  info.wireBytes = wireBudget-wire
  CurrentRefreshPlanResult[CurrentRefreshPlan](status: CurrentRefreshPlanError.None,
    completed: CurrentRefreshPlan(initialized: true, source: source, limits: limits, info: info))
proc refreshPlanSource*(source: CurrentRefreshPlan): CurrentRefreshPlanResult[CurrentRequestKeys] =
  ## Retain only the original immutable cached identities and genuine actual target.
  if not source.initialized: return CurrentRefreshPlanResult[CurrentRequestKeys](
      status: CurrentRefreshPlanError.Uninitialized)
  CurrentRefreshPlanResult[CurrentRequestKeys](status: CurrentRefreshPlanError.None,
      completed: source.source)
proc refreshPlanLimits*(source: CurrentRefreshPlan): CurrentRefreshPlanResult[
    CurrentRefreshLimits] =
  ## Return detached fixed policies; mutating this value never changes an existing plan's quotas.
  if not source.initialized: return CurrentRefreshPlanResult[CurrentRefreshLimits](
      status: CurrentRefreshPlanError.Uninitialized)
  CurrentRefreshPlanResult[CurrentRefreshLimits](status: CurrentRefreshPlanError.None,
      completed: source.limits)
proc refreshPlanInfo*(source: CurrentRefreshPlan): CurrentRefreshPlanResult[CurrentRefreshInfo] =
  ## Copy exact whole-output accounting without exporting arrays or construction authority.
  if not source.initialized: return CurrentRefreshPlanResult[CurrentRefreshInfo](
      status: CurrentRefreshPlanError.Uninitialized)
  CurrentRefreshPlanResult[CurrentRefreshInfo](status: CurrentRefreshPlanError.None,
      completed: source.info)
