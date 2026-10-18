# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated actual/default public and private work-queue result reads require their exact
## success contract.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
include ../../src/codec/state_workqueues
var fixture: seq[byte] = @[]
# Independent report fixture bytes are required setup, never parent-decoder-derived expectations.
try:
  let text = readFile(paramStr(3))
  fixture = newSeq[byte](text.len)
  # Copy explicit octets without relying on string/sequence layouts.
  for i in 0..<text.len: fixture[i] = byte(text[i])
except:
  # A setup failure must not count as a success-precondition rejection.
  quit 2
let useDefault = paramStr(2) == "default"
let policy = WorkQueueConfig(epochSlots: EpochSlots(2), cores: CoreCount(2), perSlot: ElementLimit(
    3), totalItems: ElementLimit(3), perDependencies: ElementLimit(3),
    totalDependencies: ElementLimit(4), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(100000))
var invalid = policy
invalid.epochSlots = EpochSlots(0)
var tiny = policy
tiny.maxBytes = ByteLimit(2)
var noItems = policy
noItems.perSlot = ElementLimit(0)
var childBytes = policy
childBytes.reportBytes = ByteLimit(1)
var noDependencies = policy
noDependencies.perDependencies = ElementLimit(0)
var hugeEpoch = policy
hugeEpoch.epochSlots = EpochSlots(high(uint64))
hugeEpoch.maxBytes = ByteLimit(high(uint64))
var huge = policy
huge.perSlot = ElementLimit(high(uint64))
huge.totalItems = ElementLimit(high(uint64))
huge.maxBytes = ByteLimit(high(uint64))
var a = default(PackageHash)
var b = default(PackageHash)
a.bytes[0] = 17
b.bytes[0] = 18
let report = decodeOwnedReport(fixture, 2)
assert report.error == OwnershipError.None
var rows = newSeq[ReadyRow](2)
rows[1] = @[ReadyItem(report: report.value, dependencies: @[a, b])]
var missing = newSeq[ReadyRow](2)
missing[1] = @[ReadyItem()]
var duplicate = newSeq[ReadyRow](2)
duplicate[1] = @[ReadyItem(report: report.value, dependencies: @[a, a])]
let history = @[@[a, b], @[a]]
let badHistory = @[@[a], @[b, a]]
let readyEntry = readyStateEntry(rows, policy)
assert readyEntry.error == WorkQueueError.None
let owner = decodeReadyState(readyEntry.value.value, policy).value.snapshot
let accEntry = accumulatedStateEntry(history, policy)
assert accEntry.error == WorkQueueError.None
let accumulated = decodeAccumulatedState(accEntry.value.value, policy).value.snapshot
# Author a complete duplicate late set without using production offsets or decoder metadata.
var badSet = @[0'u8, 2]
# Two zero identities duplicate the late set's key even though its fixed extent is complete.
for i in 0..<64: badSet.add(0'u8)
var hugeCount = @[255'u8]
# Canonical uint64 maximum cannot authorize an unrepresentable fixed hash row.
for i in 0..<8: hugeCount.add(255'u8)
var cursor = 0
case paramStr(1)
of "ready-entry-config":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, invalid)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidConfig)
  discard parsed.value.value.len
of "ready-entry-count":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidCount)
  discard parsed.value.value.len
of "ready-entry-policy":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, noItems)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of "ready-entry-report":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(missing, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidReport)
  discard parsed.value.value.len
of "ready-entry-child":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, childBytes)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of "ready-entry-dependencies":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, noDependencies)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of "ready-entry-order":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(duplicate, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.value.len
of "ready-entry-bytes":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, tiny)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of "acc-entry-count":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: accumulatedStateEntry([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidCount)
  discard parsed.value.value.len
of "acc-entry-order":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: accumulatedStateEntry(
      badHistory, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.value.len
of "acc-entry-policy":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: accumulatedStateEntry(
      history, noItems)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of "ready-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.snapshot
of "ready-consumed":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.consumed
of "ready-config":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], invalid)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidConfig)
  discard parsed.value.consumed
of "ready-overflow":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], hugeEpoch)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LengthOverflow)
  discard parsed.value.consumed
of "ready-framing":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([0'u8, 128, 0], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.consumed
of "ready-child":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([0'u8, 1], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.consumed
of "ready-dependencies":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState(readyEntry.value.value, noDependencies)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.consumed
of "ready-bytes":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState(readyEntry.value.value, tiny)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.consumed
of "acc-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.snapshot
of "acc-consumed":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.consumed
of "acc-order":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState(badSet, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.consumed
of "acc-overflow":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState(hugeCount, huge)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LengthOverflow)
  discard parsed.value.consumed
of "ready-info":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueInfo]) else: readyInfo(default(ReadySnapshot))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.items
of "acc-info":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueInfo]) else: accumulatedInfo(default(AccumulatedSnapshot))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.items
of "ready-slot-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: readySlotCount(default(
      ReadySnapshot), WorkQueueSlot(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value
of "ready-slot-index":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: readySlotCount(owner,
      WorkQueueSlot(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value
of "acc-slot-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: accumulatedSlotCount(default(
      AccumulatedSnapshot), WorkQueueSlot(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value
of "acc-slot-index":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: accumulatedSlotCount(accumulated,
      WorkQueueSlot(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value
of "item-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[ReadyItemInfo]) else: readyItemAt(default(
      ReadySnapshot), WorkQueueSlot(0), ReadyItemIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.report
of "item-slot":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[ReadyItemInfo]) else: readyItemAt(owner,
      WorkQueueSlot(high(uint64)), ReadyItemIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.dependencies
of "item-index":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[ReadyItemInfo]) else: readyItemAt(owner,
      WorkQueueSlot(1), ReadyItemIndex(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.dependencies
of "dep-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(default(
      ReadySnapshot), WorkQueueSlot(0), ReadyItemIndex(0), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.bytes
of "dep-slot":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(owner,
      WorkQueueSlot(high(uint64)), ReadyItemIndex(0), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of "dep-item":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(owner,
      WorkQueueSlot(1), ReadyItemIndex(high(uint64)), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of "dep-index":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(owner,
      WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of "hash-owner":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: accumulatedHashAt(default(
      AccumulatedSnapshot), WorkQueueSlot(0), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.bytes
of "hash-slot":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: accumulatedHashAt(
      accumulated, WorkQueueSlot(high(uint64)), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of "hash-index":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: accumulatedHashAt(
      accumulated, WorkQueueSlot(0), WorkQueueHashIndex(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of "count-truncated":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[uint64]) else: readCount([], cursor, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value
of "count-noncanonical":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[uint64]) else: readCount([128'u8, 0], cursor, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value
of "ready-layout":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[Layout]) else: scan([0'u8, 128, 0], policy, true)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.dependencies
of "acc-layout":
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[Layout]) else: scan(badSet, policy, false)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.consumed
else:
  # Unknown trusted modes cannot masquerade as expected access rejections.
  assert false
