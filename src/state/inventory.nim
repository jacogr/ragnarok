# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compact service facts retain exact logical declarations bound to one complete matched source.
## Payload bytes stay in the existing source; callers cannot substitute mutable declarations later.
import ../codec/[bounded, composite]
import ../codec/state/[layout as state_layout, accounts as state_accounts,
    composition as state_composition, service_values as state_service_values]
import ./manifest

type
  InventoryServiceIndex* = distinct uint64 ## Ordinal belongs to this captured declaration order, not a service identity.
  InventoryStorageIndex* = distinct uint64 ## Storage fact ordinals cannot select preimages or requests.
  InventoryPreimageIndex* = distinct uint64 ## Preimage fact ordinals belong to one service row.
  InventoryRequestIndex* = distinct uint64 ## Request fact ordinals belong to one service row.
  StateInventoryLimits* = object ## Revalidation, retained fact count and native descriptor bytes are independent.
    manifest*: StateManifestLimits
    facts*: ElementLimit
    bytes*: ByteLimit
  InventoryStorageFact* = object ## Fixed source-bound physical identity and original logical extents, excluding namespace overhead.
    key*: StateKey
    keyBytes*, valueBytes*: uint64
  InventoryPreimageFact* = object ## Content remains in the source; this fact supplies its original logical hash and exact extent.
    key*: StateKey
    hash*: ServicePreimageHash
    bytes*: uint64
  InventoryServiceInfo* = object ## Metadata and child counts are copied fixed observations, never construction authority.
    service*: ServiceIndex
    metadata*: ServiceMetadata
    storage*, preimages*, requests*: int
  StateInventoryInfo* = object ## Retained allocation/accounting observations do not confer state validity.
    services*: int
    facts*, descriptorBytes*: uint64
  StateInventoryError* {.pure.} = enum ## Refusal/default alternatives carry no compact prefix or complete source.
    Uninitialized, None, InvalidSource, LimitExceeded, ManifestFailure, KeyFailure, InvalidIndex, NoService
  ServiceRow = object # All arrays are private immutable fixed facts after publication.
    info: InventoryServiceInfo
    storage: seq[InventoryStorageFact]
    preimages: seq[InventoryPreimageFact]
    requests: seq[StateRequestItem]
  InventoryData = ref object # Source and fixed arrays form an acyclic retained graph.
    source: ValidatedStateManifest
    rows: seq[ServiceRow]
    info: StateInventoryInfo
  StateInventory* = object ## Only exact checked capture creates a logical inventory of the full declared mapping.
    data: nil InventoryData
  StateInventoryResult*[T] = object ## Private alternatives preserve success and nested-reason contracts.
    case status: StateInventoryError
    of None:
      completed: T
    of ManifestFailure:
      manifestReason: StateManifestResult[ValidatedStateManifest]
    of KeyFailure:
      keyReason: ServiceValueError
    else:
      discard

func error*[T](outcome: StateInventoryResult[T]): StateInventoryError =
  ## Read the reason without allowing retagging or payload mutation.
  outcome.status

func value*[T](outcome: StateInventoryResult[T]): T {.inline,
    requires: outcome.status == StateInventoryError.None.} =
  ## Read only complete success under checked optimized contracts.
  outcome.completed

func manifestFailure*[T](outcome: StateInventoryResult[T]): StateManifestResult[
    ValidatedStateManifest] {.inline,

requires: outcome.status == StateInventoryError.ManifestFailure.} =
  ## Preserve the genuinely failed exact-map validation result.
  outcome.manifestReason

func keyError*[T](outcome: StateInventoryResult[T]): ServiceValueError {.inline,
    requires: outcome.status == StateInventoryError.KeyFailure.} =
  ## Expose only an actual compact-fact key derivation refusal.
  outcome.keyReason

proc captureStateInventory*(source: ValidatedStateManifest, services: openArray[StateService],
    limits: StateInventoryLimits): StateInventoryResult[StateInventory] =
  ## Borrow declarations synchronously, recheck every byte against the source, and retain only compact detached facts.
  template fail(reason: StateInventoryError) =
    return StateInventoryResult[StateInventory](status: reason)
  if source.manifestInfo.error != StateManifestError.None:
    fail(StateInventoryError.InvalidSource) # Defaults cannot supply complete source authority.
  if uint64(services.len) > uint64(limits.manifest.services):
    fail(StateInventoryError.LimitExceeded) # Bound every descriptor inspection before traversal.
  var facts = uint64(limits.facts)
  var bytes = min(uint64(limits.bytes), uint64(high(int)))
  let availableBytes = bytes
  template charge(count: int, kind: untyped) =
    block:
      let amount = uint64(count)
      if amount > facts or amount > bytes div uint64(sizeof(kind)):
        fail(StateInventoryError.LimitExceeded) # Prove both multiplication and native allocation before any output construction.
      facts -= amount
      bytes -= amount * uint64(sizeof(kind))
  charge(services.len, ServiceRow)
  for item in services:
    charge(item.storage.len, InventoryStorageFact)
    charge(item.preimages.len, InventoryPreimageFact)
    charge(item.requests.len, StateRequestItem) # Count every retained descriptor, including zero-length values.
  let checked = validateStateManifest(source.manifestGlobals.value, services, limits.manifest)
  if checked.error != StateManifestError.None:
    return StateInventoryResult[StateInventory](status: StateInventoryError.ManifestFailure,
      manifestReason: checked) # Mutable declarations cannot replace facts belonging to a different mapping.
  var rows = newSeq[ServiceRow](services.len)
  for index, item in services:
    rows[index] = ServiceRow(info: InventoryServiceInfo(service: item.service,
      metadata: item.metadata,
      storage: item.storage.len, preimages: item.preimages.len, requests: item.requests.len),
      storage: newSeq[InventoryStorageFact](item.storage.len),
      preimages: newSeq[InventoryPreimageFact](item.preimages.len),
      requests: newSeq[StateRequestItem](item.requests.len))
    for ordinal, value in item.storage:
      let key = serviceStorageKey(item.service, value.key, limits.manifest.storageKeyBytes)
      if key.error != ServiceValueError.None:
        return StateInventoryResult[StateInventory](status: StateInventoryError.KeyFailure,
          keyReason: key.error) # No partial service row escapes a late backend refusal.
      rows[index].storage[ordinal] = InventoryStorageFact(key: key.value,
        keyBytes: uint64(value.key.len), valueBytes: uint64(value.value.len))
    for ordinal, value in item.preimages:
      let key = servicePreimageKey(item.service, value.hash, ByteLimit(32))
      if key.error != ServiceValueError.None:
        return StateInventoryResult[StateInventory](status: StateInventoryError.KeyFailure,
          keyReason: key.error) # Content identity is copied only after successful exact key derivation.
      rows[index].preimages[ordinal] = InventoryPreimageFact(key: key.value, hash: value.hash,
        bytes: uint64(value.value.len))
    for ordinal, value in item.requests:
      rows[index].requests[ordinal] = value # Hash, length and tagged history are fixed values without borrowed backing arrays.
  StateInventoryResult[StateInventory](status: StateInventoryError.None,
    completed: StateInventory(data: InventoryData(source: source, rows: rows,
      info: StateInventoryInfo(services: services.len, facts: uint64(limits.facts)-facts,
        descriptorBytes: availableBytes-bytes))))

proc inventoryInfo*(inventory: StateInventory): StateInventoryResult[StateInventoryInfo] =
  ## Copy full inventory accounting without exposing private storage.
  let data = inventory.data
  if data == nil: return StateInventoryResult[StateInventoryInfo](
      status: StateInventoryError.Uninitialized) # Default owner.
  StateInventoryResult[StateInventoryInfo](status: StateInventoryError.None, completed: data.info)

proc inventorySource*(inventory: StateInventory): StateInventoryResult[ValidatedStateManifest] =
  ## Retain the exact original matched source, never a recomputed replacement owner.
  let data = inventory.data
  if data == nil: return StateInventoryResult[ValidatedStateManifest](
      status: StateInventoryError.Uninitialized) # Default owner.
  StateInventoryResult[ValidatedStateManifest](status: StateInventoryError.None,
      completed: data.source)

proc inventoryServiceAt*(inventory: StateInventory,
    index: InventoryServiceIndex): StateInventoryResult[InventoryServiceInfo] =
  ## Copy one metadata/count row after validating the full unsigned ordinal.
  let data = inventory.data
  if data == nil: return StateInventoryResult[InventoryServiceInfo](
      status: StateInventoryError.Uninitialized) # No source.
  if uint64(index) >= uint64(data.rows.len): return StateInventoryResult[InventoryServiceInfo](
      status: StateInventoryError.InvalidIndex) # No narrowing before bounds.
  StateInventoryResult[InventoryServiceInfo](status: StateInventoryError.None, completed: data.rows[
      int(uint64(index))].info)

proc inventoryStorageAt*(inventory: StateInventory, service: InventoryServiceIndex,
    index: InventoryStorageIndex): StateInventoryResult[InventoryStorageFact] =
  ## Copy one owner-bound storage fact without exposing mutable arrays or accepting another ordinal domain.
  let data = inventory.data
  if data == nil: return StateInventoryResult[InventoryStorageFact](
      status: StateInventoryError.Uninitialized) # No source.
  if uint64(service) >= uint64(data.rows.len): return StateInventoryResult[InventoryStorageFact](
      status: StateInventoryError.InvalidIndex) # Validate service first.
  if uint64(index) >= uint64(data.rows[int(uint64(
      service))].storage.len): return StateInventoryResult[InventoryStorageFact](
      status: StateInventoryError.InvalidIndex) # Full-width child bound precedes narrowing.
  StateInventoryResult[InventoryStorageFact](status: StateInventoryError.None,
    completed: data.rows[int(uint64(service))].storage[int(uint64(index))])

proc inventoryPreimageAt*(inventory: StateInventory, service: InventoryServiceIndex,
    index: InventoryPreimageIndex): StateInventoryResult[InventoryPreimageFact] =
  ## Copy one owner-bound preimages fact without exposing mutable arrays or accepting another ordinal domain.
  let data = inventory.data
  if data == nil: return StateInventoryResult[InventoryPreimageFact](
      status: StateInventoryError.Uninitialized) # No source.
  if uint64(service) >= uint64(data.rows.len): return StateInventoryResult[InventoryPreimageFact](
      status: StateInventoryError.InvalidIndex) # Validate service first.
  if uint64(index) >= uint64(data.rows[int(uint64(
      service))].preimages.len): return StateInventoryResult[InventoryPreimageFact](
      status: StateInventoryError.InvalidIndex) # Full-width child bound precedes narrowing.
  StateInventoryResult[InventoryPreimageFact](status: StateInventoryError.None,
    completed: data.rows[int(uint64(service))].preimages[int(uint64(index))])

proc inventoryRequestAt*(inventory: StateInventory, service: InventoryServiceIndex,
    index: InventoryRequestIndex): StateInventoryResult[StateRequestItem] =
  ## Copy one owner-bound requests fact without exposing mutable arrays or accepting another ordinal domain.
  let data = inventory.data
  if data == nil: return StateInventoryResult[StateRequestItem](
      status: StateInventoryError.Uninitialized) # No source.
  if uint64(service) >= uint64(data.rows.len): return StateInventoryResult[StateRequestItem](
      status: StateInventoryError.InvalidIndex) # Validate service first.
  if uint64(index) >= uint64(data.rows[int(uint64(
      service))].requests.len): return StateInventoryResult[StateRequestItem](
      status: StateInventoryError.InvalidIndex) # Full-width child bound precedes narrowing.
  StateInventoryResult[StateRequestItem](status: StateInventoryError.None,
    completed: data.rows[int(uint64(service))].requests[int(uint64(index))])

func sameStateInventory*(left, right: StateInventory): bool =
  ## Compare initialized exact logical captures by owner identity; equal maps and default handles do not match.
  left.data != nil and left.data == right.data
