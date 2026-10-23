# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded detached reconstruction of supplied service declarations from retained logical keys and original payloads.
## Projection hashes nothing and confers no authority on mutable output declarations.
import ../codec/[bounded, state_composition]
import ./[supplied_logical_inventory, inventory, manifest, store]
type
  SuppliedServicesLimits* = object ## Every copied service/child descriptor, raw key and payload is charged before allocating output arrays.
    services*, facts*: ElementLimit
    perValue*, bytes*: ByteLimit
  SuppliedServicesError* {.pure.} = enum ## Default input and resource refusal never produce successful empty declarations.
    Uninitialized, None, InvalidSource, LimitExceeded, InvalidPlan
  SuppliedServicesResult* = object ## Private mutable output is accessible only through successful bounded projection.
    case status: SuppliedServicesError
    of None:
      completed: seq[StateService]
    else:
      discard # No partially reconstructed service array escapes refusal.
func error*(outcome: SuppliedServicesResult): SuppliedServicesError =
  ## Observe immutable selection without retagging.
  outcome.status
func value*(outcome: SuppliedServicesResult): seq[StateService] {.inline,
    requires: outcome.status == SuppliedServicesError.None.} =
  ## Return fully detached mutable declarations only after complete projection succeeds.
  outcome.completed
type
  SuppliedServicesInfo* = object ## Exact whole-copy ledger records admitted native descriptors and copied raw key/payload extents.
    services*: int
    facts*, bytes*: uint64
  SuppliedServicesPlan* = object ## Immutable qualified logical source and projection policies cannot be substituted after admission.
    initialized: bool
    source: SuppliedLogicalInventory
    limits: SuppliedServicesLimits
    info: SuppliedServicesInfo
  SuppliedServicesPlanResult*[T] = object ## Default and refused planning expose no partial declaration array or source/policy prefix.
    case status: SuppliedServicesError
    of None: completed: T
    else: discard # Only complete admission grants a plan or ledger.
func error*[T](outcome: SuppliedServicesPlanResult[T]): SuppliedServicesError =
  ## Preserve original source and quota categories for one-shot and staged projection.
  outcome.status
func value*[T](outcome: SuppliedServicesPlanResult[T]): T {.inline, requires: outcome.status ==
    SuppliedServicesError.None.} =
  ## Extract only admitted immutable plans and copied observations.
  outcome.completed
proc planSuppliedServices*(source: SuppliedLogicalInventory,
    limits: SuppliedServicesLimits): SuppliedServicesPlanResult[SuppliedServicesPlan] =
  ## Admit the entire exact output before any raw key or payload is copied.
  template fail(reason: SuppliedServicesError) =
    return SuppliedServicesPlanResult[SuppliedServicesPlan](status: reason)
  let captured = source.suppliedInventory
  if captured.error != SuppliedLogicalError.None:
    fail(SuppliedServicesError.InvalidSource)
  let inventory = captured.value
  let count = inventory.inventoryInfo.value.services
  if uint64(count) > uint64(limits.services):
    fail(SuppliedServicesError.LimitExceeded) # Bound full service traversal before inspecting child descriptors.
  var available = min(uint64(limits.bytes), uint64(high(int)))
  let budget = available
  var facts = uint64(limits.facts)
  template charge(count: int, kind: untyped) =
    block:
      let amount = uint64(count)
      if amount > facts or amount > available div uint64(sizeof(kind)):
        fail(SuppliedServicesError.LimitExceeded) # Joint count/descriptor proof precedes narrowing and allocation.
      facts -= amount
      available -= amount * uint64(sizeof(kind))
  template payload(size: uint64) =
    block:
      let extent = size
      if extent > uint64(limits.perValue) or extent > available:
        fail(SuppliedServicesError.LimitExceeded) # Subtraction bounds all copied raw-key/value bytes including zero lengths.
      available -= extent
  charge(count, StateService)
  for i in 0..<count:
    let service = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(service).value
    charge(row.storage, StateStorageItem)
    charge(row.preimages, StatePreimageItem)
    charge(row.requests, StateRequestItem)
    for j in 0..<row.storage:
      let fact = inventory.inventoryStorageAt(service, InventoryStorageIndex(uint64(j))).value
      payload(fact.keyBytes)
      payload(fact.valueBytes)
    for j in 0..<row.preimages:
      payload(inventory.inventoryPreimageAt(service, InventoryPreimageIndex(uint64(j))).value.bytes)
  SuppliedServicesPlanResult[SuppliedServicesPlan](status: SuppliedServicesError.None,
    completed: SuppliedServicesPlan(initialized: true, source: source, limits: limits,
      info: SuppliedServicesInfo(services: count, facts: uint64(limits.facts)-facts,
          bytes: budget-available)))
proc suppliedServicesPlanInfo*(plan: SuppliedServicesPlan): SuppliedServicesPlanResult[
    SuppliedServicesInfo] =
  ## Observe fixed whole-output accounting without exposing source or mutable policy storage.
  if not plan.initialized: return SuppliedServicesPlanResult[SuppliedServicesInfo](
      status: SuppliedServicesError.InvalidPlan)
  SuppliedServicesPlanResult[SuppliedServicesInfo](status: SuppliedServicesError.None,
      completed: plan.info)
proc executeSuppliedServices*(plan: SuppliedServicesPlan): SuppliedServicesResult =
  ## Reconstruct detached declarations only from the frozen originally qualified source.
  if not plan.initialized: return SuppliedServicesResult(status: SuppliedServicesError.InvalidPlan)
  let inventory = plan.source.suppliedInventory.value
  let count = plan.info.services
  let limits = plan.limits
  let snapshot = inventory.inventorySource.value.manifestSource.value
  var output = newSeq[StateService](count)
  for i in 0..<count:
    let service = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(service).value
    output[i] = StateService(service: row.service, metadata: row.metadata, storage: newSeq[
        StateStorageItem](row.storage), preimages: newSeq[StatePreimageItem](row.preimages),
        requests: newSeq[StateRequestItem](row.requests))
    for j in 0..<row.storage:
      let ordinal = InventoryStorageIndex(uint64(j))
      let fact = inventory.inventoryStorageAt(service, ordinal).value
      output[i].storage[j] = StateStorageItem(key: plan.source.copySuppliedStorageKey(service,
          ordinal, limits.perValue).value, value: snapshot.lookup(
          fact.key).value.bytes) # Key and payload copy-out are independently detached from retained storage.
    for j in 0..<row.preimages:
      let fact = inventory.inventoryPreimageAt(service, InventoryPreimageIndex(uint64(j))).value
      output[i].preimages[j] = StatePreimageItem(hash: fact.hash, value: snapshot.lookup(
          fact.key).value.bytes)
    for j in 0..<row.requests:
      output[i].requests[j] = inventory.inventoryRequestAt(service, InventoryRequestIndex(uint64(
          j))).value # Request history is a fixed immutable value, with no borrowed array.
  SuppliedServicesResult(status: SuppliedServicesError.None, completed: output)
proc copySuppliedServices*(source: SuppliedLogicalInventory,
    limits: SuppliedServicesLimits): SuppliedServicesResult =
  ## Preserve one-shot behavior through the same whole-output admission and detached execution path.
  let plan = planSuppliedServices(source, limits)
  if plan.error != SuppliedServicesError.None:
    return SuppliedServicesResult(status: plan.error)
  executeSuppliedServices(plan.value)
