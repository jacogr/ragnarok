# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retain bounded supplied raw storage keys alongside an exact revalidated compact inventory.
## Payloads stay in the original immutable snapshot; supplied declarations are not a producer manifest or execution authority.
import ../codec/bounded as codec_bounded
import ../codec/state_composition as codec_state_composition
import ./manifest as state_manifest
import ./inventory as state_inventory
type
  SuppliedLogicalLimits* = object ## Compact descriptors, extra raw-key counts, raw bytes and all extra retained array bytes have independent limits.
    inventory*: StateInventoryLimits
    keys*: ElementLimit
    rawKeyBytes*, bytes*: ByteLimit
  SuppliedLogicalInfo* = object ## Copied accounting describes extra retained arrays, excluding the separately bounded compact inventory.
    services*: int
    keys*, rawKeyBytes*, descriptorBytes*, retainedBytes*: uint64
  LogicalServiceRow = object # Raw storage key order is private and fixed to this captured service/storage ordinal.
    keys: seq[seq[byte]]
  LogicalInventoryData = ref object # Acyclic original compact/source owner plus extra copied keys, never copied payloads.
    inventory: StateInventory
    rows: seq[LogicalServiceRow]
    info: SuppliedLogicalInfo
  SuppliedLogicalInventory* = object ## Only full original-source matching constructs an immutable supplied logical description.
    data: nil LogicalInventoryData
  SuppliedLogicalError* {.pure.} = enum ## Invalid source, bounded refusal and original nested capture failure grant no partial key owner.
    Uninitialized, None, InvalidSource, LimitExceeded, InventoryFailure, InvalidIndex
  SuppliedLogicalResult*[T] = object ## Private alternatives guard source/key access and preserve genuinely failed compact capture.
    case status: SuppliedLogicalError
    of None:
      completed: T
    of InventoryFailure:
      inventoryReason: StateInventoryResult[StateInventory]
    else:
      discard # Defaults and failed admission contain no successful prefix.
func error*[T](outcome: SuppliedLogicalResult[T]): SuppliedLogicalError =
  ## Observe selected immutable alternatives only.
  outcome.status
func value*[T](outcome: SuppliedLogicalResult[T]): T {.inline, requires: outcome.status ==
    SuppliedLogicalError.None.} =
  ## Extract only initialized successful owners, fixed observations or detached copies.
  outcome.completed
func inventoryFailure*[T](outcome: SuppliedLogicalResult[T]): StateInventoryResult[
    StateInventory] {.inline, requires: outcome.status == SuppliedLogicalError.InventoryFailure.} =
  ## Preserve original exact manifest/compact refusal without supplying an empty successful inventory.
  outcome.inventoryReason
proc captureSuppliedLogicalInventory*(source: ValidatedStateManifest, services: openArray[
    StateService], limits: SuppliedLogicalLimits): SuppliedLogicalResult[SuppliedLogicalInventory] =
  ## Borrow stable complete declarations synchronously; admit every extra descriptor/key byte before hashing, allocation or copying.
  template fail(reason: SuppliedLogicalError) =
    return SuppliedLogicalResult[SuppliedLogicalInventory](status: reason)
  if source.manifestInfo.error != StateManifestError.None:
    fail(SuppliedLogicalError.InvalidSource)
  if uint64(services.len) > uint64(limits.inventory.manifest.services):
    fail(SuppliedLogicalError.LimitExceeded) # Bound descriptor traversal before nested inspection.
  var available = min(uint64(limits.bytes), uint64(high(int)))
  let admittedBytes = available
  var keys = uint64(limits.keys)
  var raw = min(uint64(limits.rawKeyBytes), uint64(high(int)))
  let admittedRaw = raw
  var descriptors = 0'u64
  template charge(count: int, kind: untyped) =
    block:
      let amount = uint64(count)
      if amount > available div uint64(sizeof(kind)):
        fail(SuppliedLogicalError.LimitExceeded) # Division proves multiplication, addition and native allocation extents.
      let size = amount * uint64(sizeof(kind))
      available -= size
      descriptors += size # Sum is bounded by admittedBytes, itself at most high(int).
  charge(services.len, LogicalServiceRow)
  for service in services:
    if uint64(service.storage.len) > keys:
      fail(SuppliedLogicalError.LimitExceeded)
    keys -= uint64(service.storage.len)
    charge(service.storage.len, seq[byte])
    for item in service.storage:
      let size = uint64(item.key.len)
      if size > uint64(limits.inventory.manifest.storageKeyBytes) or size > raw or size > available:
        fail(SuppliedLogicalError.LimitExceeded) # Empty keys remain present; aggregate subtraction proves addition safety.
      raw -= size
      available -= size
  let captured = captureStateInventory(source, services, limits.inventory)
  if captured.error != StateInventoryError.None:
    return SuppliedLogicalResult[SuppliedLogicalInventory](
        status: SuppliedLogicalError.InventoryFailure,
        inventoryReason: captured) # Duplicate/opaque/incomplete supplied declarations cannot replace original authority.
  var rows = newSeq[LogicalServiceRow](services.len)
  for i, service in services:
    rows[i].keys = newSeq[seq[byte]](service.storage.len)
    for j, item in service.storage:
      rows[i].keys[j] = newSeq[byte](item.key.len)
      for k, octet in item.key:
        rows[i].keys[j][k] = octet # Every key is copied after whole-source admission; caller buffer mutation cannot alter retained identity.
  SuppliedLogicalResult[SuppliedLogicalInventory](status: SuppliedLogicalError.None,
    completed: SuppliedLogicalInventory(data: LogicalInventoryData(inventory: captured.value,
      rows: rows,
      info: SuppliedLogicalInfo(services: services.len, keys: uint64(limits.keys)-keys,
          rawKeyBytes: admittedRaw-raw, descriptorBytes: descriptors,
          retainedBytes: admittedBytes-available))))
proc suppliedLogicalInfo*(source: SuppliedLogicalInventory): SuppliedLogicalResult[
    SuppliedLogicalInfo] =
  ## Copy fixed extra-retention accounting without exposing raw-key backing arrays.
  let data = source.data
  if data == nil:
    return SuppliedLogicalResult[SuppliedLogicalInfo](status: SuppliedLogicalError.Uninitialized)
  SuppliedLogicalResult[SuppliedLogicalInfo](status: SuppliedLogicalError.None,
      completed: data.info)
proc suppliedInventory*(source: SuppliedLogicalInventory): SuppliedLogicalResult[StateInventory] =
  ## Retain the exact internally captured compact inventory and its original full snapshot identity.
  let data = source.data
  if data == nil:
    return SuppliedLogicalResult[StateInventory](status: SuppliedLogicalError.Uninitialized)
  SuppliedLogicalResult[StateInventory](status: SuppliedLogicalError.None,
      completed: data.inventory)
proc copySuppliedStorageKey*(source: SuppliedLogicalInventory, service: InventoryServiceIndex,
    storage: InventoryStorageIndex, limit: ByteLimit): SuppliedLogicalResult[seq[byte]] =
  ## Validate nominal full-width ordinals and explicit copy extent before allocating a detached raw key, including present-empty keys.
  let data = source.data
  if data == nil:
    return SuppliedLogicalResult[seq[byte]](status: SuppliedLogicalError.Uninitialized)
  if uint64(service) >= uint64(data.rows.len):
    return SuppliedLogicalResult[seq[byte]](status: SuppliedLogicalError.InvalidIndex)
  let row = int(uint64(service))
  if uint64(storage) >= uint64(data.rows[row].keys.len):
    return SuppliedLogicalResult[seq[byte]](status: SuppliedLogicalError.InvalidIndex)
  let item = int(uint64(storage))
  let size = data.rows[row].keys[item].len
  if uint64(size) > uint64(limit):
    return SuppliedLogicalResult[seq[byte]](status: SuppliedLogicalError.LimitExceeded)
  var owned = newSeq[byte](size)
  for i in 0..<size:
    owned[i] = data.rows[row].keys[item][i] # Copy by index without iterating through the retained ref.
  SuppliedLogicalResult[seq[byte]](status: SuppliedLogicalError.None, completed: owned)
