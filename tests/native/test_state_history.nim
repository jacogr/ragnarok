## Whole-parent retention, dictionary association, peak presence, copied fields and result/index guards.
import ../../src/codec/[state_history, bounded, assurances]

## Failed/default results cannot expose a fabricated value, snapshot or consumed cursor.
proc guarded[T](parsed: HistoryResult[T]) =
  var caught = false
  try:
    discard parsed.value # Inactive success alternatives must fail even under optimized builds.
  except FieldDefect:
    caught = true # The checked ARC/Clang LTO contract retains variant field guards.
  doAssert caught

## Assert an absent copied peak contains no readable default hash field.
proc absentGuard(peak: HistoryPeak) =
  var caught = false
  try:
    discard peak.hash # Absence and present-zero are distinct application states.
  except FieldDefect:
    caught = true # Preserve the optional value's own discriminator guard.
  doAssert caught

## Verify parent/dictionary/peak copies survive input destruction and handle/value replacement.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(HistoryPeak) == 33 and sizeof(ReportedPackage) == 64
  let config = HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(128), maxBytes: ByteLimit(10_000))
  var a, b: array[32, byte]
  a[0] = 17
  b[0] = 23
  var source = HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(a),
      superPeak: HistorySuperPeak(b),
    state: HistoryStateRoot(default(array[32, byte])), slot: HistorySlot(0x01020304),
    packages: @[ReportedPackage(package: PackageHash(bytes: a), segment: SegmentRoot(bytes: b))])],
    peaks: @[HistoryPeak(present: false), HistoryPeak(present: true, hash: HistoryPeakHash(default(
        array[32, byte]))),
      HistoryPeak(present: false)])
  let encoded = historyStateEntry(source, config)
  doAssert encoded.error == HistoryError.None
  doAssert array[31, byte](encoded.value.key)[0] == 3
  source.blocks[0].packages[0].segment.bytes[0] = 255
  doAssert encoded.value.value[1+100+1+32] == 23
  var wire = encoded.value.value
  let parsed = decodeHistoryState(wire, config)
  doAssert parsed.error == HistoryError.None
  let retained = parsed.value.snapshot
  source = default(HistoryState)
  # Destroy caller input after complete immutable capture.
  for i in 0..<wire.len: wire[i] = 0
  let info = historyInfo(retained)
  doAssert info.error == HistoryError.None and info.value.blocks == 1 and info.value.peaks == 3
  let record = historyBlockAt(retained, HistoryBlockIndex(0))
  doAssert record.error == HistoryError.None and uint32(record.value.slot) == 0x01020304
  doAssert array[32, byte](record.value.superPeak)[0] == 23
  let pair = historyPackageAt(retained, HistoryBlockIndex(0), HistoryPackageIndex(0))
  doAssert pair.error == HistoryError.None and pair.value.package.bytes[0] == 17 and
      pair.value.segment.bytes[0] == 23
  var copy = pair.value
  copy.segment.bytes[0] = 255
  doAssert historyPackageAt(retained, HistoryBlockIndex(0), HistoryPackageIndex(
      0)).value.segment.bytes[0] == 23
  let absent = historyPeakAt(retained, HistoryPeakIndex(0))
  doAssert absent.error == HistoryError.None and not absent.value.present
  absentGuard(absent.value)
  let zero = historyPeakAt(retained, HistoryPeakIndex(1))
  doAssert zero.error == HistoryError.None and zero.value.present
  doAssert array[32, byte](zero.value.hash) == default(array[32, byte])
  var replaced = retained
  replaced = default(HistorySnapshot)
  doAssert historyInfo(retained).value.peaks == 3
  guarded(historyInfo(replaced))
  guarded(historyPackageAt(replaced, HistoryBlockIndex(0), HistoryPackageIndex(0)))
  let badBlock = historyBlockAt(retained, HistoryBlockIndex(high(uint64)))
  doAssert badBlock.error == HistoryError.InvalidIndex
  guarded(badBlock)
  let badPair = historyPackageAt(retained, HistoryBlockIndex(0), HistoryPackageIndex(high(uint64)))
  doAssert badPair.error == HistoryError.InvalidIndex
  guarded(badPair)
  let badPeak = historyPeakAt(retained, HistoryPeakIndex(high(uint64)))
  doAssert badPeak.error == HistoryError.InvalidIndex
  guarded(badPeak)
  guarded(default(HistoryResult[HistoryRead]))
  let empty = historyStateEntry(default(HistoryState), config)
  doAssert empty.error == HistoryError.None and empty.value.value == @[0'u8, 0]
  let short = decodeHistoryState(@[0'u8], config)
  doAssert short.error == HistoryError.Truncated
  guarded(short)
  echo "PASS history state: immutable parent/dictionaries, copied fields, optional peaks and result/index guards"

main()
