# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-parent retention, dictionary association, peak presence, copied fields and result/index guards.
import std/[assertions, syncio]
import ../../../src/codec/[state_history, bounded, assurances]

## Verify parent/dictionary/peak copies survive input destruction and handle/value replacement.
proc main() =
  assert sizeof(int) == 8 and sizeof(HistoryPeak) == 33 and sizeof(ReportedPackage) == 64
  let config = HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(128), maxBytes: ByteLimit(10_000))
  var a = default(array[32, byte])
  var b = default(array[32, byte])
  a[0] = 17
  b[0] = 23
  var source = HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(a),
      superPeak: HistorySuperPeak(b),
    state: HistoryStateRoot(default(array[32, byte])), slot: HistorySlot(0x01020304),
    packages: @[ReportedPackage(package: PackageHash(bytes: a), segment: SegmentRoot(bytes: b))])],
    peaks: @[absentHistoryPeak(), presentHistoryPeak(HistoryPeakHash(default(array[32, byte]))),
      absentHistoryPeak()])
  let encoded = historyStateEntry(source, config)
  assert encoded.error == HistoryError.None
  assert array[31, byte](encoded.value.key)[0] == 3
  source.blocks[0].packages[0].segment.bytes[0] = 255
  assert encoded.value.value[1+100+1+32] == 23
  var wire = encoded.value.value
  let parsed = decodeHistoryState(wire, config)
  assert parsed.error == HistoryError.None
  let retained = parsed.value.snapshot
  source = default(HistoryState)
  # Destroy caller input after complete immutable capture.
  for i in 0..<wire.len: wire[i] = 0
  let info = historyInfo(retained)
  assert info.error == HistoryError.None and info.value.blocks == 1 and info.value.peaks == 3
  let record = historyBlockAt(retained, HistoryBlockIndex(0))
  assert record.error == HistoryError.None and uint32(record.value.slot) == 0x01020304
  assert array[32, byte](record.value.superPeak)[0] == 23
  let pair = historyPackageAt(retained, HistoryBlockIndex(0), HistoryPackageIndex(0))
  assert pair.error == HistoryError.None and pair.value.package.bytes[0] == 17 and
      pair.value.segment.bytes[0] == 23
  var copy = pair.value
  copy.segment.bytes[0] = 255
  assert historyPackageAt(retained, HistoryBlockIndex(0), HistoryPackageIndex(
      0)).value.segment.bytes[0] == 23
  let absent = historyPeakAt(retained, HistoryPeakIndex(0))
  assert absent.error == HistoryError.None and not absent.value.present
  let zero = historyPeakAt(retained, HistoryPeakIndex(1))
  assert zero.error == HistoryError.None and zero.value.present
  assert array[32, byte](zero.value.hash) == default(array[32, byte])
  var replaced = retained
  replaced = default(HistorySnapshot)
  assert historyInfo(retained).value.peaks == 3
  let badBlock = historyBlockAt(retained, HistoryBlockIndex(high(uint64)))
  assert badBlock.error == HistoryError.InvalidIndex
  let badPair = historyPackageAt(retained, HistoryBlockIndex(0), HistoryPackageIndex(high(uint64)))
  assert badPair.error == HistoryError.InvalidIndex
  let badPeak = historyPeakAt(retained, HistoryPeakIndex(high(uint64)))
  assert badPeak.error == HistoryError.InvalidIndex
  let empty = historyStateEntry(default(HistoryState), config)
  assert empty.error == HistoryError.None and empty.value.value == @[0'u8, 0]
  let short = decodeHistoryState(@[0'u8], config)
  assert short.error == HistoryError.Truncated
  echo "PASS history state: immutable parent/dictionaries, copied fields, optional peaks and result/index guards"

main()
