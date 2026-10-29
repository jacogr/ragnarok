# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "failure_driver"}

## Isolated actual/default public and private work-queue result reads require their exact
## success contract.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
include ../../src/codec/state/workqueues
import ../support/probe_cases

## Declared misuse modes; custom strings preserve CLI labels and typed dispatch is exhaustive.
# @@ProbeCases
type VerificationProbe = enum
  vpAccConsumed = "acc-consumed"
  vpAccEntryCount = "acc-entry-count"
  vpAccEntryOrder = "acc-entry-order"
  vpAccEntryPolicy = "acc-entry-policy"
  vpAccInfo = "acc-info"
  vpAccLayout = "acc-layout"
  vpAccOrder = "acc-order"
  vpAccOverflow = "acc-overflow"
  vpAccOwner = "acc-owner"
  vpAccSlotIndex = "acc-slot-index"
  vpAccSlotOwner = "acc-slot-owner"
  vpCountNoncanonical = "count-noncanonical"
  vpCountTruncated = "count-truncated"
  vpDepIndex = "dep-index"
  vpDepItem = "dep-item"
  vpDepOwner = "dep-owner"
  vpDepSlot = "dep-slot"
  vpHashIndex = "hash-index"
  vpHashOwner = "hash-owner"
  vpHashSlot = "hash-slot"
  vpItemIndex = "item-index"
  vpItemOwner = "item-owner"
  vpItemSlot = "item-slot"
  vpReadyBytes = "ready-bytes"
  vpReadyChild = "ready-child"
  vpReadyConfig = "ready-config"
  vpReadyConsumed = "ready-consumed"
  vpReadyDependencies = "ready-dependencies"
  vpReadyEntryBytes = "ready-entry-bytes"
  vpReadyEntryChild = "ready-entry-child"
  vpReadyEntryConfig = "ready-entry-config"
  vpReadyEntryCount = "ready-entry-count"
  vpReadyEntryDependencies = "ready-entry-dependencies"
  vpReadyEntryOrder = "ready-entry-order"
  vpReadyEntryPolicy = "ready-entry-policy"
  vpReadyEntryReport = "ready-entry-report"
  vpReadyFraming = "ready-framing"
  vpReadyInfo = "ready-info"
  vpReadyLayout = "ready-layout"
  vpReadyOverflow = "ready-overflow"
  vpReadyOwner = "ready-owner"
  vpReadySlotIndex = "ready-slot-index"
  vpReadySlotOwner = "ready-slot-owner"

# Validate selection or list declarations before reading any runtime fixture.
let selectedProbe = selectProbe[VerificationProbe](paramStr(1))
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
case selectedProbe
of vpReadyEntryConfig:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, invalid)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidConfig)
  discard parsed.value.value.len
of vpReadyEntryCount:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidCount)
  discard parsed.value.value.len
of vpReadyEntryPolicy:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, noItems)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of vpReadyEntryReport:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(missing, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidReport)
  discard parsed.value.value.len
of vpReadyEntryChild:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, childBytes)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of vpReadyEntryDependencies:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, noDependencies)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of vpReadyEntryOrder:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(duplicate, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.value.len
of vpReadyEntryBytes:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: readyStateEntry(rows, tiny)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of vpAccEntryCount:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: accumulatedStateEntry([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidCount)
  discard parsed.value.value.len
of vpAccEntryOrder:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: accumulatedStateEntry(
      badHistory, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.value.len
of vpAccEntryPolicy:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[StateEntry]) else: accumulatedStateEntry(
      history, noItems)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.value.len
of vpReadyOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.snapshot
of vpReadyConsumed:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.consumed
of vpReadyConfig:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], invalid)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidConfig)
  discard parsed.value.consumed
of vpReadyOverflow:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([], hugeEpoch)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LengthOverflow)
  discard parsed.value.consumed
of vpReadyFraming:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([0'u8, 128, 0], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.consumed
of vpReadyChild:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState([0'u8, 1], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.consumed
of vpReadyDependencies:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState(readyEntry.value.value, noDependencies)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.consumed
of vpReadyBytes:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      ReadySnapshot]]) else: decodeReadyState(readyEntry.value.value, tiny)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LimitExceeded)
  discard parsed.value.consumed
of vpAccOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.snapshot
of vpAccConsumed:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState([], policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value.consumed
of vpAccOrder:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState(badSet, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.consumed
of vpAccOverflow:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueRead[
      AccumulatedSnapshot]]) else: decodeAccumulatedState(hugeCount, huge)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.LengthOverflow)
  discard parsed.value.consumed
of vpReadyInfo:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueInfo]) else: readyInfo(default(ReadySnapshot))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.items
of vpAccInfo:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[WorkQueueInfo]) else: accumulatedInfo(default(AccumulatedSnapshot))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.items
of vpReadySlotOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: readySlotCount(default(
      ReadySnapshot), WorkQueueSlot(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value
of vpReadySlotIndex:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: readySlotCount(owner,
      WorkQueueSlot(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value
of vpAccSlotOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: accumulatedSlotCount(default(
      AccumulatedSnapshot), WorkQueueSlot(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value
of vpAccSlotIndex:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[int]) else: accumulatedSlotCount(accumulated,
      WorkQueueSlot(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value
of vpItemOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[ReadyItemInfo]) else: readyItemAt(default(
      ReadySnapshot), WorkQueueSlot(0), ReadyItemIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.report
of vpItemSlot:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[ReadyItemInfo]) else: readyItemAt(owner,
      WorkQueueSlot(high(uint64)), ReadyItemIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.dependencies
of vpItemIndex:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[ReadyItemInfo]) else: readyItemAt(owner,
      WorkQueueSlot(1), ReadyItemIndex(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.dependencies
of vpDepOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(default(
      ReadySnapshot), WorkQueueSlot(0), ReadyItemIndex(0), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.bytes
of vpDepSlot:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(owner,
      WorkQueueSlot(high(uint64)), ReadyItemIndex(0), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of vpDepItem:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(owner,
      WorkQueueSlot(1), ReadyItemIndex(high(uint64)), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of vpDepIndex:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: readyDependencyAt(owner,
      WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of vpHashOwner:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: accumulatedHashAt(default(
      AccumulatedSnapshot), WorkQueueSlot(0), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidOwner)
  discard parsed.value.bytes
of vpHashSlot:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: accumulatedHashAt(
      accumulated, WorkQueueSlot(high(uint64)), WorkQueueHashIndex(0))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of vpHashIndex:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[PackageHash]) else: accumulatedHashAt(
      accumulated, WorkQueueSlot(0), WorkQueueHashIndex(high(uint64)))
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.InvalidIndex)
  discard parsed.value.bytes
of vpCountTruncated:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[uint64]) else: readCount([], cursor, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.Truncated)
  discard parsed.value
of vpCountNoncanonical:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[uint64]) else: readCount([128'u8, 0], cursor, policy)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value
of vpReadyLayout:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[Layout]) else: scan([0'u8, 128, 0], policy, true)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.dependencies
of vpAccLayout:
  # Defaults and these actual failures cannot authorize values, owners or partial progress.
  let parsed = if useDefault: default(WorkQueueResult[Layout]) else: scan(badSet, policy, false)
  assert parsed.error == (if useDefault: WorkQueueError.Uninitialized else: WorkQueueError.NonCanonical)
  discard parsed.value.consumed
