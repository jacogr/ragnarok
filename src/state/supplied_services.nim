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
    Uninitialized, None, InvalidSource, LimitExceeded
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
proc copySuppliedServices*(source: SuppliedLogicalInventory,
    limits: SuppliedServicesLimits): SuppliedServicesResult =
  ## Admit all native array descriptors and copied extents before copying any key/value, then rebuild from the original source only.
  template fail(reason: SuppliedServicesError) =
    return SuppliedServicesResult(status: reason)
  let captured = source.suppliedInventory
  if captured.error != SuppliedLogicalError.None:
    fail(SuppliedServicesError.InvalidSource)
  let inventory = captured.value
  let count = inventory.inventoryInfo.value.services
  if uint64(count) > uint64(limits.services):
    fail(SuppliedServicesError.LimitExceeded) # Bound full service traversal before inspecting child descriptors.
  var available = min(uint64(limits.bytes), uint64(high(int)))
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
      output[i].storage[j] = StateStorageItem(key: source.copySuppliedStorageKey(service, ordinal,
          limits.perValue).value, value: snapshot.lookup(
          fact.key).value.bytes) # Key and payload copy-out are independently detached from retained storage.
    for j in 0..<row.preimages:
      let fact = inventory.inventoryPreimageAt(service, InventoryPreimageIndex(uint64(j))).value
      output[i].preimages[j] = StatePreimageItem(hash: fact.hash, value: snapshot.lookup(
          fact.key).value.bytes)
    for j in 0..<row.requests:
      output[i].requests[j] = inventory.inventoryRequestAt(service, InventoryRequestIndex(uint64(
          j))).value # Request history is a fixed immutable value, with no borrowed array.
  SuppliedServicesResult(status: SuppliedServicesError.None, completed: output)
