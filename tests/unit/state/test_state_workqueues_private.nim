# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../support/arc_evidence
## Project-only ready/accumulated lifetime, copied-child and arithmetic checks; no private runtime hooks.
import std/[assertions, envvars, syncio]
include ../../../src/codec/state_workqueues
var fixture: seq[byte] = @[]
# Fixture bytes come from the independent Python report equations and must be available before testing.
try:
  assert getEnv("RAGNAROK_STATE_REPORT").len > 0, "missing independent report fixture"
  let text = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  fixture = newSeq[byte](text.len)
  # Copy explicit octets without representation casts.
  for i in 0..<text.len: fixture[i] = byte(text[i])
except:
  # Missing setup cannot count as successful lifetime coverage.
  quit 2

## Small independent item/dependency/byte policies retain fixed slot framing and opaque child ownership.
proc policy(): WorkQueueConfig =
  WorkQueueConfig(epochSlots: EpochSlots(2), cores: CoreCount(2), perSlot: ElementLimit(3),
    totalItems: ElementLimit(3), perDependencies: ElementLimit(3), totalDependencies: ElementLimit(4),
    reportBytes: ByteLimit(100000), maxBytes: ByteLimit(100000))

## Construct canonical copied hashes directly with marker-dependent first octets.
proc hash(marker: byte): PackageHash =
  result = default(PackageHash)
  result.bytes[0] = marker

## Repeated reports remain an ordered sequence, with independent selected dependency sets.
proc readySource(bytes: openArray[byte], marker: byte): seq[ReadyRow] =
  let report = decodeOwnedReport(bytes, 2)
  assert report.error == OwnershipError.None
  result = newSeq[ReadyRow](2)
  result[1] = @[ReadyItem(report: report.value, dependencies: @[hash(marker), hash(marker+1)]),
    ReadyItem(report: report.value)]

## Canonical accumulated rows preserve slot position and repeated identities across separate sets.
proc accumulatedSource(marker: byte): seq[AccumulatedRow] =
  @[@[hash(marker), hash(marker+1)], @[hash(marker)]]

## Escape a ready parent after all local report/dependency sources and mutable input retire.
proc escapedReady(bytes: openArray[byte], marker: byte): ReadySnapshot =
  var rows = readySource(bytes, marker)
  let entry = readyStateEntry(rows, policy())
  assert entry.error == WorkQueueError.None
  var wire = entry.value.value
  let parsed = decodeReadyState(wire, policy())
  assert parsed.error == WorkQueueError.None
  result = parsed.value.snapshot
  rows = @[]
  # Parent and child data must survive every original byte being destroyed.
  for i in 0..<wire.len: wire[i] = 0

## Escape an accumulated parent after source sets and original wire retire.
proc escapedAccumulated(marker: byte): AccumulatedSnapshot =
  var rows = accumulatedSource(marker)
  let entry = accumulatedStateEntry(rows, policy())
  assert entry.error == WorkQueueError.None
  var wire = entry.value.value
  let parsed = decodeAccumulatedState(wire, policy())
  assert parsed.error == WorkQueueError.None
  result = parsed.value.snapshot
  rows = @[]
  # Fixed identities cannot retain detached coordinates into this caller buffer.
  for i in 0..<wire.len: wire[i] = 0

## Retain only a report after its callee-local parent and dependency arrays lose their final references.
proc escapedReport(bytes: openArray[byte]): OwnedReport =
  let owner = escapedReady(bytes, 61)
  readyItemAt(owner, WorkQueueSlot(1), ReadyItemIndex(0)).value.report

## Each scope releases both parent schemas, aliases, report children, fixed copies and failed temporaries.
proc cycle(bytes: openArray[byte]) =
  var ready = escapedReady(bytes, 17)
  let alias = ready
  ready = escapedReady(bytes, 29)
  assert readyInfo(alias).value.items == 2 and readyInfo(alias).value.dependencies == 2
  assert readySlotCount(alias, WorkQueueSlot(0)).value == 0
  assert readyDependencyAt(ready, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 29
  var info = readyInfo(alias).value
  info.items = 0
  assert readyInfo(alias).value.items == 2
  var item = readyItemAt(alias, WorkQueueSlot(1), ReadyItemIndex(0)).value
  item.report = default(OwnedReport)
  item.dependencies = 0
  assert readyItemAt(alias, WorkQueueSlot(1), ReadyItemIndex(0)).value.dependencies == 2
  var copied = readyDependencyAt(alias, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(0)).value
  copied.bytes[0] = 0
  assert readyDependencyAt(alias, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  ready = default(ReadySnapshot)
  assert readyInfo(ready).error == WorkQueueError.InvalidOwner
  assert readyInfo(alias).value.slots == 2
  assert readyDependencyAt(alias, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(high(
      uint64))).error == WorkQueueError.InvalidIndex
  assert readyItemAt(alias, WorkQueueSlot(1), ReadyItemIndex(high(uint64))).error ==
      WorkQueueError.InvalidIndex
  assert readySlotCount(alias, WorkQueueSlot(high(uint64))).error == WorkQueueError.InvalidIndex
  let child = escapedReport(bytes)
  var replay = newSeq[byte](bytes.len)
  assert encodeOwnedReport(child, replay).error == OwnershipError.None
  assert replay == bytes
  var accumulated = escapedAccumulated(43)
  let history = accumulated
  accumulated = escapedAccumulated(71)
  assert accumulatedHashAt(history, WorkQueueSlot(0), WorkQueueHashIndex(0)).value.bytes[0] == 43
  assert accumulatedHashAt(accumulated, WorkQueueSlot(1), WorkQueueHashIndex(0)).value.bytes[0] == 71
  var metadata = accumulatedInfo(history).value
  metadata.items = 0
  assert accumulatedInfo(history).value.items == 3
  accumulated = default(AccumulatedSnapshot)
  assert accumulatedInfo(accumulated).error == WorkQueueError.InvalidOwner
  assert accumulatedHashAt(history, WorkQueueSlot(0), WorkQueueHashIndex(high(uint64))).error ==
      WorkQueueError.InvalidIndex
  var readyWire = readyStateEntry(readySource(bytes, 17), policy()).value.value
  # The final report's zero dependency count becomes an overlong zero after all earlier valid work.
  readyWire[readyWire.len-1] = 128
  readyWire.add(0'u8)
  let beforeReady = getOccupiedMem()
  assert decodeReadyState(readyWire, policy()).error == WorkQueueError.NonCanonical
  assert beforeReady == getOccupiedMem()
  var bad = accumulatedSource(17)
  # Keep the total within policy so the intended late ordering failure is reached.
  bad[0] = @[]
  bad[1] = @[hash(18), hash(17)]
  var historyWire = @[0'u8, 2]
  # A complete late descending set rejects after an earlier empty valid slot.
  for b in hash(18).bytes: historyWire.add(b)
  # Keep the second complete fixed identity in its authored descending order.
  for b in hash(17).bytes: historyWire.add(b)
  let beforeHistory = getOccupiedMem()
  assert decodeAccumulatedState(historyWire, policy()).error == WorkQueueError.NonCanonical
  assert beforeHistory == getOccupiedMem()
  assert accumulatedStateEntry(bad, policy()).error == WorkQueueError.NonCanonical
  let emptyReady = decodeReadyState([0'u8, 0], policy()).value.snapshot
  let emptyHistory = decodeAccumulatedState([0'u8, 0], policy()).value.snapshot
  assert readyInfo(emptyReady).value.items == 0 and accumulatedInfo(emptyHistory).value.items == 0

# Descriptor bounds and metadata arithmetic are tested without fake sequences or announced-size allocation.
var huge = policy()
huge.maxBytes = ByteLimit(high(uint64))
huge.perSlot = ElementLimit(high(uint64))
huge.totalItems = ElementLimit(high(uint64))
huge.perDependencies = ElementLimit(high(uint64))
huge.totalDependencies = ElementLimit(high(uint64))
var cursor = high(int)-32
assert grow(cursor, 1, 32, huge) == WorkQueueError.None
assert cursor == high(int)
assert grow(cursor, 1, 1, huge) == WorkQueueError.LengthOverflow
assert cursor == high(int)
assert grow(cursor, 0, 32, huge) == WorkQueueError.None
cursor = 0
assert grow(cursor, high(uint64), 32, huge) == WorkQueueError.LengthOverflow
assert cursor == 0
var total = uint64(high(int))
assert chargeItems(1, sizeof(ReadyItem), huge, total) == WorkQueueError.LengthOverflow
assert total == uint64(high(int))
assert chargeDependencies(1, huge, total) == WorkQueueError.LengthOverflow
assert total == uint64(high(int))
total = 0
assert chargeItems(high(uint64), sizeof(PackageHash), huge, total) == WorkQueueError.LengthOverflow
assert chargeDependencies(high(uint64), huge, total) == WorkQueueError.LengthOverflow
assert total == 0
huge.epochSlots = EpochSlots(uint64(high(int) div sizeof(ReadyRow)))
assert validate(huge) == WorkQueueError.None
huge.epochSlots = EpochSlots(uint64(high(int) div sizeof(ReadyRow))+1)
assert validate(huge) == WorkQueueError.LengthOverflow
# Warm up report capture and allocator bookkeeping before the isolated scoped comparison.
for i in 0..<100: cycle(fixture)
let beforeRelease = getOccupiedMem()
# Final parent/report references and all nested arrays/copies retire at scope exit.
for i in 0..<1000: cycle(fixture)
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_workqueues_private", 1000, beforeRelease, afterRelease)
echo "WORKQUEUES_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony chapters 14/15: retained/replaced rings, escaped reports, copied sets and scoped ARC release passed"
