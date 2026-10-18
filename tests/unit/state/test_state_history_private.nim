# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only lifetime, optional-value and arithmetic checks using public allocator observations.
import std/[assertions, syncio]
import ../../support/arc_evidence
include ../../../src/codec/state_history

## Explicit tiny-profile resource ceilings retain all history, dictionary and optional framing.
proc policy(): HistoryConfig =
  HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(128), maxBytes: ByteLimit(10000))

## Direct source fields preserve dictionary associations and distinguish absent from present-zero peaks.
proc source(marker: byte): HistoryState =
  var key = default(array[32, byte])
  var segment = default(array[32, byte])
  key[0] = marker
  segment[0] = marker+1
  HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(key), superPeak: HistorySuperPeak(segment),
    state: HistoryStateRoot(key), slot: HistorySlot(0x01020304), packages: @[
    ReportedPackage(package: PackageHash(bytes: key), segment: SegmentRoot(bytes: segment))])],
    peaks: @[absentHistoryPeak(), presentHistoryPeak(HistoryPeakHash(default(array[32, byte]))),
      presentHistoryPeak(HistoryPeakHash(key)), absentHistoryPeak()])

## Retain only private copied storage after local sources, entry and mutable wire aliases retire.
proc escaped(marker: byte): HistorySnapshot =
  var original = source(marker)
  let entry = historyStateEntry(original, policy())
  assert entry.error == HistoryError.None
  var wire = entry.value.value
  let parsed = decodeHistoryState(wire, policy())
  assert parsed.error == HistoryError.None
  result = parsed.value.snapshot
  original = default(HistoryState)
  # Destroy every caller byte after whole-parent capture.
  for i in 0..<wire.len: wire[i] = 0

## Every scope retires retained/replaced parents and all copied metadata, dictionary and optional values.
proc cycle() =
  var owner = escaped(17)
  let alias = owner
  owner = escaped(29)
  assert historyPackageAt(alias, HistoryBlockIndex(0), HistoryPackageIndex(0)).value.segment.bytes[0] == 18
  assert historyPackageAt(owner, HistoryBlockIndex(0), HistoryPackageIndex(0)).value.package.bytes[0] == 29
  var info = historyInfo(alias).value
  info.blocks = 0
  assert historyInfo(alias).value.blocks == 1
  var blockInfo = historyBlockAt(alias, HistoryBlockIndex(0)).value
  blockInfo.header = default(HistoryHeaderHash)
  blockInfo.slot = HistorySlot(0)
  assert array[32, byte](historyBlockAt(alias, HistoryBlockIndex(0)).value.header)[0] == 17
  assert uint32(historyBlockAt(alias, HistoryBlockIndex(0)).value.slot) == 0x01020304
  var pair = historyPackageAt(alias, HistoryBlockIndex(0), HistoryPackageIndex(0)).value
  pair.segment = default(SegmentRoot)
  assert historyPackageAt(alias, HistoryBlockIndex(0), HistoryPackageIndex(0)).value.segment.bytes[0] == 18
  assert not historyPeakAt(alias, HistoryPeakIndex(0)).value.present
  assert historyPeakAt(alias, HistoryPeakIndex(1)).value.present
  assert array[32, byte](historyPeakAt(alias, HistoryPeakIndex(1)).value.hash) == default(array[32, byte])
  var peak = historyPeakAt(alias, HistoryPeakIndex(2)).value
  peak = absentHistoryPeak()
  assert array[32, byte](historyPeakAt(alias, HistoryPeakIndex(2)).value.hash)[0] == 17
  assert not historyPeakAt(alias, HistoryPeakIndex(3)).value.present
  owner = default(HistorySnapshot)
  assert historyInfo(owner).error == HistoryError.InvalidOwner
  assert historyInfo(alias).value.peaks == 4
  assert historyPackageAt(alias, HistoryBlockIndex(high(uint64)), HistoryPackageIndex(0)).error ==
      HistoryError.InvalidIndex
  assert historyPackageAt(alias, HistoryBlockIndex(0), HistoryPackageIndex(high(uint64))).error ==
      HistoryError.InvalidIndex
  assert historyPeakAt(alias, HistoryPeakIndex(high(uint64))).error == HistoryError.InvalidIndex
  var original = source(43)
  var wire = historyStateEntry(original, policy()).value.value
  wire[wire.len-1] = 2
  let before = getOccupiedMem()
  assert decodeHistoryState(wire, policy()).error == HistoryError.InvalidTag
  assert before == getOccupiedMem()
  original.blocks[0].packages.add(ReportedPackage(package: PackageHash(bytes: default(array[32, byte]))))
  assert historyStateEntry(original, policy()).error == HistoryError.NonCanonical
  let empty = decodeHistoryState([0'u8, 0], policy()).value.snapshot
  assert historyInfo(empty).value.blocks == 0
  assert historyPeakAt(empty, HistoryPeakIndex(0)).error == HistoryError.InvalidIndex

# Arithmetic probes reach the host ceiling without fabricated descriptors or advertised-size allocations.
var cursor = high(int)-64
assert grow(cursor, 1, 64, ByteLimit(high(uint64))) == HistoryError.None
assert cursor == high(int)
assert grow(cursor, 1, 1, ByteLimit(high(uint64))) == HistoryError.LengthOverflow
assert cursor == high(int)
assert grow(cursor, 0, 33, ByteLimit(high(uint64))) == HistoryError.None
cursor = high(int)-32
assert grow(cursor, 1, 33, ByteLimit(high(uint64))) == HistoryError.LengthOverflow
assert cursor == high(int)-32
cursor = 0
assert grow(cursor, high(uint64), 64, ByteLimit(high(uint64))) == HistoryError.LengthOverflow
assert cursor == 0
var huge = policy()
huge.cores = CoreCount(high(uint64))
huge.perBlock = ElementLimit(high(uint64))
huge.totalPackages = ElementLimit(high(uint64))
var total = 0'u64
assert packageCount(high(uint64), huge, total) == HistoryError.LengthOverflow
assert total == 0
huge.totalPackages = ElementLimit(1)
total = 1
assert packageCount(1, huge, total) == HistoryError.LimitExceeded
assert total == 1
# Warm up public allocator bookkeeping before comparing the isolated scoped workload.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# All source arrays, parent aliases, optional copies and failure temporaries retire at scope exit.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_history_private", 1000, beforeRelease, afterRelease)
echo "HISTORY_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony chapter 3: retained/replaced history, associated dictionaries, optional copies and scoped ARC release passed"
