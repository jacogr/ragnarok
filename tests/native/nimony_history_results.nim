## Isolated public/internal result failures and absent optional hashes require their exact contracts.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_history
let useDefault = paramStr(2) == "default"
let policy = HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
    totalPackages: ElementLimit(16), peaks: ElementLimit(128), maxBytes: ByteLimit(10000))
var invalid = policy
invalid.cores = CoreCount(0)
var tiny = policy
tiny.maxBytes = ByteLimit(1)
var strictBlocks = policy
strictBlocks.blocks = ElementLimit(0)
var strictPeaks = policy
strictPeaks.peaks = ElementLimit(0)
var huge = policy
huge.peaks = ElementLimit(high(uint64))
huge.maxBytes = ByteLimit(high(uint64))
let pair = default(ReportedPackage)
let record = HistoryBlock(packages: @[pair])
let original = HistoryState(blocks: @[record], peaks: @[absentHistoryPeak(), presentHistoryPeak(
    default(HistoryPeakHash))])
let many = HistoryState(blocks: newSeq[HistoryBlock](9))
let manyPairs = HistoryState(blocks: @[HistoryBlock(packages: @[pair, pair, pair])])
let duplicate = HistoryState(blocks: @[HistoryBlock(packages: @[pair, pair])])
let encoded = historyStateEntry(original, policy)
assert encoded.error == HistoryError.None
let owner = decodeHistoryState(encoded.value.value, policy).value.snapshot
# Literal complete fixed fields precede the excessive or duplicate dictionary count.
var badPairs = @[1'u8]
# No production encoder supplies hostile count framing or duplicate-key expected results.
for i in 0..<100: badPairs.add(0'u8)
var badOrder = badPairs
badPairs.add(3'u8)
badOrder.add(2'u8)
# Two complete zero key/value pairs are a duplicate dictionary even with a valid final belt count.
for i in 0..<128: badOrder.add(0'u8)
badOrder.add(0'u8)
case paramStr(1)
of "entry-config":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(original, invalid)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidConfig)
  discard parsed.value.value.len
of "entry-count":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(many, policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidCount)
  discard parsed.value.value.len
of "entry-policy":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(original, strictBlocks)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.LimitExceeded)
  discard parsed.value.value.len
of "entry-pairs":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(manyPairs, policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidCount)
  discard parsed.value.value.len
of "entry-order":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(duplicate, policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.NonCanonical)
  discard parsed.value.value.len
of "entry-peaks":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(original, strictPeaks)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.LimitExceeded)
  discard parsed.value.value.len
of "entry-bytes":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[StateEntry]) else: historyStateEntry(original, tiny)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.LimitExceeded)
  discard parsed.value.value.len
of "decode-config":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([], invalid)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidConfig)
  discard parsed.value.consumed
of "decode-count":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([9'u8], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidCount)
  discard parsed.value.consumed
of "decode-framing":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([128'u8,
      0], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.NonCanonical)
  discard parsed.value.consumed
of "decode-pairs":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState(badPairs, policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidCount)
  discard parsed.value.consumed
of "decode-order":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState(badOrder, policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.NonCanonical)
  discard parsed.value.consumed
of "decode-tag":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([0'u8, 1,
      2], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidTag)
  discard parsed.value.consumed
of "decode-peaks":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([0'u8,
      1], strictPeaks)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.LimitExceeded)
  discard parsed.value.consumed
of "decode-bytes":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState(
      encoded.value.value, tiny)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.LimitExceeded)
  discard parsed.value.consumed
of "decode-overflow":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([0'u8,
      255, 255, 255, 255, 255, 255, 255, 255, 255], huge)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.LengthOverflow)
  discard parsed.value.consumed
of "owner":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.Truncated)
  discard parsed.value.snapshot
of "consumed":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryRead]) else: decodeHistoryState([], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.Truncated)
  discard parsed.value.consumed
of "info":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryInfo]) else: historyInfo(default(HistorySnapshot))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidOwner)
  discard parsed.value.blocks
of "block-owner":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryBlockInfo]) else: historyBlockAt(default(
      HistorySnapshot), HistoryBlockIndex(0))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidOwner)
  discard parsed.value.slot
of "block-index":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryBlockInfo]) else: historyBlockAt(owner,
      HistoryBlockIndex(high(uint64)))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidIndex)
  discard parsed.value.slot
of "package-owner":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[ReportedPackage]) else: historyPackageAt(
      default(HistorySnapshot), HistoryBlockIndex(0), HistoryPackageIndex(0))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidOwner)
  discard parsed.value.segment
of "package-block":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[ReportedPackage]) else: historyPackageAt(owner,
      HistoryBlockIndex(high(uint64)), HistoryPackageIndex(0))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidIndex)
  discard parsed.value.segment
of "package-index":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[ReportedPackage]) else: historyPackageAt(owner,
      HistoryBlockIndex(0), HistoryPackageIndex(high(uint64)))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidIndex)
  discard parsed.value.package
of "peak-owner":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryPeak]) else: historyPeakAt(default(
      HistorySnapshot), HistoryPeakIndex(0))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidOwner)
  discard parsed.value.present
of "peak-index":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[HistoryPeak]) else: historyPeakAt(owner,
      HistoryPeakIndex(high(uint64)))
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidIndex)
  discard parsed.value.present
of "count-value":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[tuple[value: uint64, size: int]]) else: count([], 0)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.Truncated)
  discard parsed.value.value
of "count-size":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[tuple[value: uint64, size: int]]) else: count([
      128'u8, 0], 0)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.NonCanonical)
  discard parsed.value.size
of "layout-blocks":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[Layout]) else: scan([0'u8], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.Truncated)
  discard parsed.value.blocks
of "layout-consumed":
  # Actual failed operations and defaults cannot authorize the selected payload or partial progress.
  let parsed = if useDefault: default(HistoryResult[Layout]) else: scan([0'u8, 1, 2], policy)
  assert parsed.error == (if useDefault: HistoryError.Uninitialized else: HistoryError.InvalidTag)
  discard parsed.value.consumed
of "absent-hash":
  # Default, explicit absence and decoded absence all prohibit inactive hash reads.
  let peak = if paramStr(2) == "default": default(HistoryPeak)
    elif paramStr(2) == "source": absentHistoryPeak()
    else: historyPeakAt(owner, HistoryPeakIndex(0)).value
  discard peak.hash
else:
  # A misspelled trusted mode must not count as a contract rejection.
  assert false
