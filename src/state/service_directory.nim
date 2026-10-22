# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded immutable service identity lookup retains one exact complete logical inventory.
## Proven absence belongs to this source; the directory grants no trusted root or STF authority.
import ../codec/[bounded, state_accounts]
import ./inventory

type
  DirectoryServiceIndex* = distinct uint64 ## Sorted-directory ordinals are separate from original capture order.
  ServiceDirectoryLimits* = object ## Retained descriptor bytes and worst-case insertion comparisons are independently bounded.
    services*, comparisons*: ElementLimit
    bytes*: ByteLimit
  ServiceDirectoryEntry* = object ## Fixed sorted service identity maps back to its original complete inventory ordinal.
    service*: ServiceIndex
    ordinal*: InventoryServiceIndex
  ServiceDirectoryInfo* = object ## Retained bytes exclude the already owned source; work is the preflighted comparison ceiling.
    services*: int
    retainedBytes*, comparisonCeiling*: uint64
  ServiceDirectoryData = ref object # Private immutable sorted array and original source form an acyclic ARC graph.
    source: StateInventory
    entries: seq[ServiceDirectoryEntry]
    info: ServiceDirectoryInfo
  StateServiceDirectory* = object ## A complete source-bound identity index, never an independently mutable service list.
    data: nil ServiceDirectoryData
  ServiceDirectoryError* {.pure.} = enum ## Exhaustive complete-source absence differs from default, index and policy refusal.
    Uninitialized, None, InvalidSource, LimitExceeded, NoService, InvalidIndex
  ServiceDirectoryResult*[T] = object ## Only complete construction or successful queries expose fixed results.
    case status: ServiceDirectoryError
    of None:
      completed: T
    else:
      discard
func error*[T](outcome: ServiceDirectoryResult[T]): ServiceDirectoryError =
  ## Read the immutable discriminator without permitting caller retagging.
  outcome.status
func value*[T](outcome: ServiceDirectoryResult[T]): T {.inline,
    requires: outcome.status == ServiceDirectoryError.None.} =
  ## Defaults and failed lookups grant no complete owner or fabricated coordinate.
  outcome.completed
proc buildStateServiceDirectory*(source: StateInventory,
    limits: ServiceDirectoryLimits): ServiceDirectoryResult[StateServiceDirectory] =
  ## Preflight native retained allocation and full insertion work before allocating or copying descriptors.
  template fail(reason: ServiceDirectoryError) =
    return ServiceDirectoryResult[StateServiceDirectory](status: reason)
  let info = source.inventoryInfo
  if info.error != StateInventoryError.None:
    fail(ServiceDirectoryError.InvalidSource) # Only an exact complete logical capture grants exhaustive service enumeration.
  let count = uint64(info.value.services)
  if count > uint64(limits.services) or
      count > min(uint64(limits.bytes), uint64(high(int))) div uint64(sizeof(
          ServiceDirectoryEntry)):
    fail(ServiceDirectoryError.LimitExceeded) # Prove retained native descriptor multiplication before allocation.
  var ceiling = 0'u64
  if count > 1:
    let a = if count mod 2 == 0: count div 2 else: count
    let b = if count mod 2 == 0: count-1 else: (count-1) div 2
    if a > uint64(limits.comparisons) div b:
      fail(ServiceDirectoryError.LimitExceeded) # Halve an even factor before bounding n(n-1)/2.
    ceiling = a * b
  var entries = newSeq[ServiceDirectoryEntry](info.value.services)
  for i in 0..<entries.len:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(ordinal).value
    let selected = ServiceDirectoryEntry(service: row.service, ordinal: ordinal)
    var position = i
    while position > 0:
      if uint32(entries[position-1].service) <= uint32(selected.service):
        break # Every row needs at most its original ordinal comparisons.
      let previousService = entries[position-1].service
      let previousOrdinal = entries[position-1].ordinal
      entries[position] = ServiceDirectoryEntry(service: previousService, ordinal: previousOrdinal)
      position -= 1 # Move fixed descriptors only; no payload or owner is duplicated per entry.
    entries[position] = selected
  ServiceDirectoryResult[StateServiceDirectory](status: ServiceDirectoryError.None,
    completed: StateServiceDirectory(data: ServiceDirectoryData(source: source, entries: entries,
      info: ServiceDirectoryInfo(services: info.value.services,
        retainedBytes: count * uint64(sizeof(ServiceDirectoryEntry)), comparisonCeiling: ceiling))))
proc directoryInfo*(directory: StateServiceDirectory): ServiceDirectoryResult[
    ServiceDirectoryInfo] =
  ## Copy completed accounting without exposing mutable index storage.
  let data = directory.data
  if data == nil:
    return ServiceDirectoryResult[ServiceDirectoryInfo](
        status: ServiceDirectoryError.Uninitialized) # Default has no complete map.
  ServiceDirectoryResult[ServiceDirectoryInfo](status: ServiceDirectoryError.None,
      completed: data.info)
proc directoryInventory*(directory: StateServiceDirectory): ServiceDirectoryResult[StateInventory] =
  ## Retain the exact original complete logical inventory.
  let data = directory.data
  if data == nil:
    return ServiceDirectoryResult[StateInventory](
        status: ServiceDirectoryError.Uninitialized) # Default has no provenance.
  ServiceDirectoryResult[StateInventory](status: ServiceDirectoryError.None, completed: data.source)
proc directoryServiceAt*(directory: StateServiceDirectory,
    index: DirectoryServiceIndex): ServiceDirectoryResult[ServiceDirectoryEntry] =
  ## Validate the full-width sorted coordinate before narrowing to the native array index.
  let data = directory.data
  if data == nil:
    return ServiceDirectoryResult[ServiceDirectoryEntry](
        status: ServiceDirectoryError.Uninitialized) # Default index.
  if uint64(index) >= uint64(data.entries.len):
    return ServiceDirectoryResult[ServiceDirectoryEntry](
        status: ServiceDirectoryError.InvalidIndex) # No modulo truncation.
  ServiceDirectoryResult[ServiceDirectoryEntry](status: ServiceDirectoryError.None,
      completed: data.entries[int(uint64(index))])
proc findService*(directory: StateServiceDirectory, service: ServiceIndex): ServiceDirectoryResult[
    InventoryServiceIndex] =
  ## Bounded binary search returns an original inventory ordinal or proven complete-source absence.
  let data = directory.data
  if data == nil:
    return ServiceDirectoryResult[InventoryServiceIndex](
        status: ServiceDirectoryError.Uninitialized) # Missing provenance is not absence.
  var low = 0
  var high = data.entries.len
  while low < high:
    let middle = low + (high-low) div 2
    let row = data.entries[middle]
    if uint32(row.service) < uint32(service):
      low = middle+1 # Only larger service identities can match.
    elif uint32(row.service) > uint32(service):
      high = middle # Only smaller service identities can match.
    else:
      return ServiceDirectoryResult[InventoryServiceIndex](status: ServiceDirectoryError.None,
          completed: row.ordinal) # Coordinate remains bound through the directory owner.
  ServiceDirectoryResult[InventoryServiceIndex](status: ServiceDirectoryError.NoService)
