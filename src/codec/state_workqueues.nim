# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T chapters 14/15 and accumulation readyspec/accumulatedspec: fixed epoch rings.
## Serialization preserves report order and canonical hash sets; it does not execute accumulation.
import std/assertions
import ./[natural, bounded, assurances, composite, work_report, report_owned, owned, state_layout, state_trie]
from ./header import EpochSlots
export EpochSlots, CoreCount, PackageHash, OwnedReport

type
  ## Slot positions belong to the fixed epoch ring, not an absolute timeslot or a report index.
  WorkQueueSlot* = distinct uint64
  ## An ordinal in one ready slot's ordered report sequence.
  ReadyItemIndex* = distinct uint64
  ## An ordinal in a dependency/accumulated set, separate from ready-report positions.
  WorkQueueHashIndex* = distinct uint64
  ## Stable source item retains its report; dependency hashes are already strictly octet-sorted and unique.
  ReadyItem* = object
    report*: OwnedReport
    dependencies*: seq[PackageHash]
  ## Source row order is significant; report identities may repeat structurally without being sorted here.
  ReadyRow* = seq[ReadyItem]
  ## One canonical accumulated package set has no mutable storage shared with retained snapshots.
  AccumulatedRow* = seq[PackageHash]
  ## Fixed epoch length plus independent row/aggregate item, dependency and complete byte ceilings.
  WorkQueueConfig* = object
    epochSlots*: EpochSlots
    cores*: CoreCount
    perSlot*, totalItems*, perDependencies*, totalDependencies*: ElementLimit
    reportBytes*, maxBytes*: ByteLimit
  ## Default and failures contain only reasons, never owners, values or consumed metadata.
  WorkQueueError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical, LimitExceeded,
    LengthOverflow, InvalidTag, InvalidReport, InvalidOwner, InvalidIndex
  ## A successful selected alternative alone exposes a complete application payload.
  WorkQueueResult*[T] = object
    case status: WorkQueueError
    of None:
      completed: T # Select success before reading retained state or a completed extent.
    else:
      discard      # Failure cannot appear to be a validated empty ring.
  ## Private acyclic storage retains immutable reports and privately copied dependency arrays.
  ReadyData = ref object
    rows: seq[ReadyRow]
    items, dependencies: int
  ## Private acyclic accumulated storage owns independently copied fixed package identities.
  AccumulatedData = ref object
    rows: seq[AccumulatedRow]
    items: int
  ## Separate value handles prevent using accumulated state as a ready-report owner.
  ReadySnapshot* = object
    data: nil ReadyData
  ## Copies share immutable private storage; replacing one handle cannot mutate another.
  AccumulatedSnapshot* = object
    data: nil AccumulatedData
  ## Prefix success binds a complete retained ring to its exact consumed extent.
  WorkQueueRead*[T] = object
    snapshot*: T
    consumed*: int
  ## Copied ring metadata exports counts alone, without mutable slot or child arrays.
  WorkQueueInfo* = object
    slots*, items*, dependencies*: int
  ## Fixed extracted metadata retains the report independently while keeping dependencies private to the parent.
  ReadyItemInfo* = object
    report*: OwnedReport
    dependencies*: int
  ## Local no-allocation scan proof publishes nothing until the whole fixed ring succeeds.
  Layout = object
    consumed, items, dependencies: int

## Failure reasons are read-only and cannot authorize values, child handles or progress.
func error*[T](value: WorkQueueResult[T]): WorkQueueError = value.status
## Complete public payloads and private scalar/layout proofs require successful selection.
func value*[T](value: WorkQueueResult[T]): T {.inline, requires: value.status ==
    WorkQueueError.None.} =
  value.completed

## Validate positive epoch/native descriptor bounds and supported report profile before traversal.
proc validate(config: WorkQueueConfig): WorkQueueError =
  if uint64(config.epochSlots) == 0 or uint64(config.cores) < 2 or uint64(config.cores) > 341:
    return WorkQueueError.InvalidConfig # Zero rings and unsupported chain profiles cannot authorize work.
  if uint64(config.epochSlots) > uint64(high(int) div sizeof(ReadyRow)):
    return WorkQueueError.LengthOverflow # Even empty retained row descriptors must fit before narrowing.
  if uint64(config.epochSlots) > uint64(config.maxBytes):
    return WorkQueueError.LimitExceeded # Every fixed slot needs at least its variable row's count byte.
  WorkQueueError.None

## Check multiplication/addition before extending a private parent extent or accessing its bytes.
proc grow(cursor: var int, count: uint64, width: int, config: WorkQueueConfig): WorkQueueError =
  if count > uint64((high(int)-cursor) div width):
    return WorkQueueError.LengthOverflow # No native arithmetic wrap.
  cursor += int(count)*width
  if uint64(cursor) > uint64(config.maxBytes):
    return WorkQueueError.LimitExceeded # All framing and payload bytes consume one parent budget.
  WorkQueueError.None

## Bound each row and aggregate typed storage before loops or input-derived allocation.
proc chargeItems(count: uint64, width: int, config: WorkQueueConfig,
    total: var uint64): WorkQueueError =
  if count > uint64(config.perSlot) or count > uint64(config.totalItems)-total:
    return WorkQueueError.LimitExceeded # Subtract remaining aggregate policy rather than overflowing an addition.
  if count > uint64(high(int) div width) or count > uint64(high(int))-total:
    return WorkQueueError.LengthOverflow # Both row storage and copied aggregate metadata must fit native addressing.
  total += count
  WorkQueueError.None

## Dependency policy is independent of report count and accumulated-history count policy.
proc chargeDependencies(count: uint64, config: WorkQueueConfig, total: var uint64): WorkQueueError =
  if count > uint64(config.perDependencies) or count > uint64(config.totalDependencies)-total:
    return WorkQueueError.LimitExceeded # Bound expensive dependency traversal before reading hashes.
  if count > uint64(high(int) div sizeof(PackageHash)) or count > uint64(high(int))-total:
    return WorkQueueError.LengthOverflow # Native array extents and metadata must remain representable.
  total += count
  WorkQueueError.None

## Read a canonical row/dependency count into private parser state, retaining no partial public cursor.
proc readCount(input: openArray[byte], cursor: var int, config: WorkQueueConfig): WorkQueueResult[uint64] =
  let parsed = natural.decode(input.toOpenArray(cursor, input.len-1))
  if not parsed.ok:
    if parsed.error == DecodeError.truncated:
      return WorkQueueResult[uint64](status: WorkQueueError.Truncated) # A missing count is not an empty set/sequence.
    else:
      return WorkQueueResult[uint64](status: WorkQueueError.NonCanonical) # Reject overlong alternate count representations.
  let error = grow(cursor, uint64(parsed.consumed), 1, config)
  if error != WorkQueueError.None:
    return WorkQueueResult[uint64](status: error) # Count bytes consume parent budget too.
  WorkQueueResult[uint64](status: WorkQueueError.None, completed: uint64(parsed.value))

## Strict octet order is independent of host endian order and rejects equal complete identities.
proc less(a, b: PackageHash): bool =
  for i in 0..<32:
    if a.bytes[i] != b.bytes[i]:
      return a.bytes[i] < b.bytes[i] # First differing byte decides canonical order.
  false

## Copy one prevalidated hash without retaining its input coordinates.
proc fixed(input: openArray[byte], offset: int): PackageHash =
  result = default(PackageHash)
  for i in 0..<32: result.bytes[i] = input[offset+i] # Caller proves the complete hash set before this access.

## Validate a full bounded fixed-hash set before reading or capturing any of its members.
proc scanHashes(input: openArray[byte], cursor: var int, count: uint64,
    config: WorkQueueConfig): WorkQueueError =
  let start = cursor
  let error = grow(cursor, count, 32, config)
  if error != WorkQueueError.None:
    return error # Announced wire arithmetic/policy precedes payload access.
  if cursor > input.len:
    return WorkQueueError.Truncated # Complete set bytes must exist before ordering reads.
  for i in 1..<int(count):
    if not less(fixed(input, start+(i-1)*32), fixed(input, start+i*32)):
      return WorkQueueError.NonCanonical # Duplicate/descending members invalidate the complete parent.
  WorkQueueError.None

## Preserve nested work-report framing causes without leaking unrelated destination/span errors.
proc reportError(error: CompositeError): WorkQueueError =
  case error
  of CompositeError.Truncated: WorkQueueError.Truncated # A required nested field is absent.
  of CompositeError.NonCanonical: WorkQueueError.NonCanonical # A child count/set/map has alternate framing.
  of CompositeError.LimitExceeded: WorkQueueError.LimitExceeded # Existing report structural/profile policy is retained.
  of CompositeError.LengthOverflow: WorkQueueError.LengthOverflow # A child extent cannot fit native addressing.
  of CompositeError.InvalidTag: WorkQueueError.InvalidTag # Unknown nested work-output tag.
  else: WorkQueueError.InvalidReport # No unexpected child status can authorize a default report.

## Scan either fixed ring completely without input-derived allocations or captured child owners.
proc scan(input: openArray[byte], config: WorkQueueConfig, ready: bool): WorkQueueResult[Layout] =
  let valid = validate(config)
  if valid != WorkQueueError.None:
    return WorkQueueResult[Layout](status: valid) # Invalid configuration precedes input traversal.
  var cursor = 0
  var items = 0'u64
  var dependencies = 0'u64
  for slot in 0..<int(uint64(config.epochSlots)):
    let count = readCount(input, cursor, config)
    if count.error != WorkQueueError.None:
      return WorkQueueResult[Layout](status: count.error) # No implicit empty late rows.
    var error = chargeItems(count.value, (if ready: sizeof(ReadyItem) else: sizeof(PackageHash)),
        config, items) # Bound the selected typed row schema.
    if error != WorkQueueError.None:
      return WorkQueueResult[Layout](status: error) # Row/aggregate limits precede child work.
    if ready:
      for i in 0..<int(count.value):
        let report = decodeReportBorrowed(input.toOpenArray(cursor, input.len-1), uint64(config.cores))
        if report.error != CompositeError.None:
          return WorkQueueResult[Layout](status: reportError(
              report.error)) # No earlier report owner after late failure.
        if uint64(report.consumed) > uint64(config.reportBytes):
          return WorkQueueResult[Layout](status: WorkQueueError.LimitExceeded) # Child bytes are independently bounded.
        error = grow(cursor, uint64(report.consumed), 1, config)
        if error != WorkQueueError.None:
          return WorkQueueResult[Layout](status: error) # Complete report contributes to parent bytes.
        let count = readCount(input, cursor, config)
        if count.error != WorkQueueError.None:
          return WorkQueueResult[Layout](status: count.error) # Each report has its own dependency count.
        error = chargeDependencies(count.value, config, dependencies)
        if error != WorkQueueError.None:
          return WorkQueueResult[Layout](status: error) # Dependency work is separate from report work.
        error = scanHashes(input, cursor, count.value, config)
        if error != WorkQueueError.None:
          return WorkQueueResult[Layout](status: error) # No partial dependency set or earlier parent escapes.
    else:
      error = scanHashes(input, cursor, count.value, config)
      if error != WorkQueueError.None:
        return WorkQueueResult[Layout](status: error) # Accumulated rows are canonical hash sets, not report sequences.
  WorkQueueResult[Layout](status: WorkQueueError.None,
    completed: Layout(consumed: cursor, items: int(items), dependencies: int(dependencies)))

## Decode chapter 14 only after every slot/report/dependency has passed the complete no-allocation scan.
proc decodeReadyState*(input: openArray[byte], config: WorkQueueConfig): WorkQueueResult[
    WorkQueueRead[ReadySnapshot]] =
  let checked = scan(input, config, true)
  if checked.error != WorkQueueError.None:
    return WorkQueueResult[WorkQueueRead[ReadySnapshot]](
        status: checked.error) # No captured child handles on failure.
  let data = ReadyData(rows: newSeq[ReadyRow](int(uint64(config.epochSlots))),
    items: checked.value.items, dependencies: checked.value.dependencies)
  var cursor = 0
  for slot in 0..<data.rows.len:
    let count = readCount(input, cursor, config).value # Repeat only proved reads over stable synchronous input.
    data.rows[slot] = newSeq[ReadyItem](int(count))
    for i in 0..<int(count):
      let report = decodeOwnedReport(input.toOpenArray(cursor, input.len-1), uint64(config.cores))
      assert report.error == OwnershipError.None # Complete parent preflight already proved this child.
      data.rows[slot][i].report = report.value
      cursor += ownedReportInfo(report.value).value.consumed
      let dependencies = readCount(input, cursor, config).value
      data.rows[slot][i].dependencies = newSeq[PackageHash](int(dependencies))
      for j in 0..<int(dependencies):
        data.rows[slot][i].dependencies[j] = fixed(input, cursor) # Private independent fixed copies.
        cursor += 32
  WorkQueueResult[WorkQueueRead[ReadySnapshot]](status: WorkQueueError.None,
    completed: WorkQueueRead[ReadySnapshot](snapshot: ReadySnapshot(data: data),
        consumed: checked.value.consumed))

## Decode chapter 15 into independent canonical hash rows after the complete ring has validated.
proc decodeAccumulatedState*(input: openArray[byte], config: WorkQueueConfig): WorkQueueResult[
    WorkQueueRead[AccumulatedSnapshot]] =
  let checked = scan(input, config, false)
  if checked.error != WorkQueueError.None:
    return WorkQueueResult[WorkQueueRead[AccumulatedSnapshot]](
        status: checked.error) # No partial earlier ring on a late bad set.
  let data = AccumulatedData(rows: newSeq[AccumulatedRow](int(uint64(config.epochSlots))),
      items: checked.value.items)
  var cursor = 0
  for slot in 0..<data.rows.len:
    let count = readCount(input, cursor, config).value # Counts and extents were already proved before allocation.
    data.rows[slot] = newSeq[PackageHash](int(count))
    for i in 0..<int(count):
      data.rows[slot][i] = fixed(input, cursor) # Do not retain caller wire or standalone coordinates.
      cursor += 32
  WorkQueueResult[WorkQueueRead[AccumulatedSnapshot]](status: WorkQueueError.None,
    completed: WorkQueueRead[AccumulatedSnapshot](snapshot: AccumulatedSnapshot(data: data),
        consumed: checked.value.consumed))

## Source hash sets must already be strictly ordered; never repair a caller's duplicates/disorder.
proc ordered(values: openArray[PackageHash]): bool =
  for i in 1..<values.len:
    if not less(values[i-1], values[i]):
      return false # Even late disorder rejects the whole entry.
  true

## Charge a source count's canonical framing before any selected row/payload validation.
proc countBytes(cursor: var int, count: int, config: WorkQueueConfig): WorkQueueError =
  grow(cursor, uint64(natural.encode(JamNatural(count)).len), 1, config)

## Write a previously sized canonical count to the fresh independent parent output.
proc putCount(output: var seq[byte], cursor: var int, count: int) =
  let encoded = natural.encode(JamNatural(count))
  for i in 0..<encoded.len:
    output[cursor] = encoded.bytes[i] # Whole-source preflight proved destination extent.
    inc cursor

## Write a validated fixed source set without a per-hash length discriminator.
proc putHashes(output: var seq[byte], cursor: var int, values: openArray[PackageHash]) =
  for value in values:
    for b in value.bytes:
      output[cursor] = b # Destination is fresh and cannot alias retained report storage or source arrays.
      inc cursor

## Encode exact fixed-epoch ready rows after complete shape, child profile, set and resource preflight.
proc readyStateEntry*(rows: openArray[ReadyRow], config: WorkQueueConfig): WorkQueueResult[StateEntry] =
  let valid = validate(config)
  if valid != WorkQueueError.None:
    return WorkQueueResult[StateEntry](status: valid) # Configuration precedes source traversal.
  if uint64(rows.len) != uint64(config.epochSlots):
    return WorkQueueResult[StateEntry](status: WorkQueueError.InvalidCount) # No outer epoch count is emitted/inferred.
  var size = 0
  var items = 0'u64
  var dependencies = 0'u64
  for row in rows:
    var error = countBytes(size, row.len, config)
    if error != WorkQueueError.None:
      return WorkQueueResult[StateEntry](status: error) # Empty slots still consume a count byte.
    error = chargeItems(uint64(row.len), sizeof(ReadyItem), config, items)
    if error != WorkQueueError.None:
      return WorkQueueResult[StateEntry](status: error) # Bound report traversal before nested owner inspection.
    for item in row:
      let info = ownedReportInfo(item.report)
      if info.error != OwnershipError.None:
        return WorkQueueResult[StateEntry](status: WorkQueueError.InvalidReport) # Default owners cannot encode fabricated reports.
      let coreOutsideProfile = uint64(info.value.core) >= uint64(config.cores)
      let shardsOutsideProfile = uint64(info.value.header.erasureShards) div 3 > uint64(config.cores)
      if coreOutsideProfile or shardsOutsideProfile:
        return WorkQueueResult[StateEntry](status: WorkQueueError.LimitExceeded) # Recheck children captured under a broader profile.
      if uint64(info.value.consumed) > uint64(config.reportBytes):
        return WorkQueueResult[StateEntry](status: WorkQueueError.LimitExceeded) # Current child-byte policy may be stricter than capture policy.
      error = grow(size, uint64(info.value.consumed), 1, config)
      if error != WorkQueueError.None:
        return WorkQueueResult[StateEntry](status: error) # Child report bytes consume parent policy.
      error = countBytes(size, item.dependencies.len, config)
      if error != WorkQueueError.None:
        return WorkQueueResult[StateEntry](status: error) # Dependency count is never omitted.
      error = chargeDependencies(uint64(item.dependencies.len), config, dependencies)
      if error != WorkQueueError.None:
        return WorkQueueResult[StateEntry](status: error) # Separate per-item/aggregate dependency ceilings.
      error = grow(size, uint64(item.dependencies.len), 32, config)
      if error != WorkQueueError.None:
        return WorkQueueResult[StateEntry](status: error) # Bound all fixed payload bytes before ordering.
      if not ordered(item.dependencies):
        return WorkQueueResult[StateEntry](status: WorkQueueError.NonCanonical) # No sorting or duplicate merging.
  var entry = StateEntry(key: chapterKey(StateChapter(14)), value: newSeq[byte](size))
  var cursor = 0
  for row in rows:
    putCount(entry.value, cursor, row.len) # Preserve epoch-slot and ordered report positions.
    for item in row:
      let length = ownedReportInfo(item.report).value.consumed
      let copied = encodeOwnedReport(item.report, entry.value.toOpenArray(cursor, cursor+length-1))
      assert copied.error == OwnershipError.None # Fresh output plus preflight proves capacity/disjointness.
      cursor += length
      putCount(entry.value, cursor, item.dependencies.len)
      putHashes(entry.value, cursor, item.dependencies)
  WorkQueueResult[StateEntry](status: WorkQueueError.None, completed: entry)

## Encode exact fixed-epoch accumulated sets atomically into one independent C(15) entry.
proc accumulatedStateEntry*(rows: openArray[AccumulatedRow],
    config: WorkQueueConfig): WorkQueueResult[StateEntry] =
  let valid = validate(config)
  if valid != WorkQueueError.None:
    return WorkQueueResult[StateEntry](status: valid) # No traversal under invalid configuration.
  if uint64(rows.len) != uint64(config.epochSlots):
    return WorkQueueResult[StateEntry](status: WorkQueueError.InvalidCount) # Fixed ring shape, without an outer count.
  var size = 0
  var total = 0'u64
  for row in rows:
    var error = countBytes(size, row.len, config)
    if error != WorkQueueError.None:
      return WorkQueueResult[StateEntry](status: error) # Empty sets still have a canonical count prefix.
    error = chargeItems(uint64(row.len), sizeof(PackageHash), config, total)
    if error != WorkQueueError.None:
      return WorkQueueResult[StateEntry](status: error) # Bound row/aggregate work before ordering.
    error = grow(size, uint64(row.len), 32, config)
    if error != WorkQueueError.None:
      return WorkQueueResult[StateEntry](status: error) # Check complete payload extent before allocation.
    if not ordered(row):
      return WorkQueueResult[StateEntry](status: WorkQueueError.NonCanonical) # Preserve canonical unique set membership.
  var entry = StateEntry(key: chapterKey(StateChapter(15)), value: newSeq[byte](size))
  var cursor = 0
  for row in rows:
    putCount(entry.value, cursor, row.len) # Slot positions never rotate during serialization.
    putHashes(entry.value, cursor, row)
  WorkQueueResult[StateEntry](status: WorkQueueError.None, completed: entry)

## Inspect copied ready-ring cardinalities without exporting nested mutable arrays.
proc readyInfo*(owner: ReadySnapshot): WorkQueueResult[WorkQueueInfo] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[WorkQueueInfo](status: WorkQueueError.InvalidOwner) # Default handles are not validated empty rings.
  WorkQueueResult[WorkQueueInfo](status: WorkQueueError.None,
    completed: WorkQueueInfo(slots: data.rows.len, items: data.items,
        dependencies: data.dependencies))

## Inspect copied accumulated-ring cardinalities; this component has no dependency sets.
proc accumulatedInfo*(owner: AccumulatedSnapshot): WorkQueueResult[WorkQueueInfo] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[WorkQueueInfo](status: WorkQueueError.InvalidOwner) # No successful counts from missing storage.
  WorkQueueResult[WorkQueueInfo](status: WorkQueueError.None,
    completed: WorkQueueInfo(slots: data.rows.len, items: data.items, dependencies: 0))

## Return one ready-slot count through a nominal ring position.
proc readySlotCount*(owner: ReadySnapshot, slot: WorkQueueSlot): WorkQueueResult[int] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[int](status: WorkQueueError.InvalidOwner) # No implicit empty default row.
  if uint64(slot) >= uint64(data.rows.len):
    return WorkQueueResult[int](status: WorkQueueError.InvalidIndex) # Check before narrowing.
  WorkQueueResult[int](status: WorkQueueError.None, completed: data.rows[int(uint64(slot))].len)

## Return one accumulated set's copied cardinality without exposing its hash array.
proc accumulatedSlotCount*(owner: AccumulatedSnapshot, slot: WorkQueueSlot): WorkQueueResult[int] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[int](status: WorkQueueError.InvalidOwner) # Default differs from a captured empty set.
  if uint64(slot) >= uint64(data.rows.len):
    return WorkQueueResult[int](status: WorkQueueError.InvalidIndex) # Prove native slot conversion.
  WorkQueueResult[int](status: WorkQueueError.None, completed: data.rows[int(uint64(slot))].len)

## Extract a copied report handle and dependency count; the report survives parent release.
proc readyItemAt*(owner: ReadySnapshot, slot: WorkQueueSlot,
    index: ReadyItemIndex): WorkQueueResult[ReadyItemInfo] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[ReadyItemInfo](status: WorkQueueError.InvalidOwner) # No storage on default handles.
  let count = readySlotCount(owner, slot)
  if count.error != WorkQueueError.None:
    return WorkQueueResult[ReadyItemInfo](status: count.error) # Owner/slot validation precedes item access.
  if uint64(index) >= uint64(count.value):
    return WorkQueueResult[ReadyItemInfo](status: WorkQueueError.InvalidIndex) # Never select unused row capacity.
  let row = int(uint64(slot))
  let position = int(uint64(index))
  WorkQueueResult[ReadyItemInfo](status: WorkQueueError.None,
    completed: ReadyItemInfo(report: data.rows[row][position].report,
      dependencies: data.rows[row][position].dependencies.len))

## Extract one dependency's fixed value through the parent, slot and selected ready-item ordinal.
proc readyDependencyAt*(owner: ReadySnapshot, slot: WorkQueueSlot, item: ReadyItemIndex,
    index: WorkQueueHashIndex): WorkQueueResult[PackageHash] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[PackageHash](status: WorkQueueError.InvalidOwner) # No storage on default handles.
  let info = readyItemAt(owner, slot, item)
  if info.error != WorkQueueError.None:
    return WorkQueueResult[PackageHash](status: info.error) # Keep the selected parent's set association.
  if uint64(index) >= uint64(info.value.dependencies):
    return WorkQueueResult[PackageHash](status: WorkQueueError.InvalidIndex) # Bound before native conversion/access.
  WorkQueueResult[PackageHash](status: WorkQueueError.None,
    completed: data.rows[int(uint64(slot))][int(uint64(item))].dependencies[int(uint64(index))])

## Extract one accumulated package hash as an independent fixed copy.
proc accumulatedHashAt*(owner: AccumulatedSnapshot, slot: WorkQueueSlot,
    index: WorkQueueHashIndex): WorkQueueResult[PackageHash] =
  let data = owner.data
  if data == nil:
    return WorkQueueResult[PackageHash](status: WorkQueueError.InvalidOwner) # No storage on default handles.
  let count = accumulatedSlotCount(owner, slot)
  if count.error != WorkQueueError.None:
    return WorkQueueResult[PackageHash](status: count.error) # Owner/slot precedes set indexing.
  if uint64(index) >= uint64(count.value):
    return WorkQueueResult[PackageHash](status: WorkQueueError.InvalidIndex) # No default hash for missing members.
  WorkQueueResult[PackageHash](status: WorkQueueError.None, completed: data.rows[int(uint64(
      slot))][int(uint64(index))])
