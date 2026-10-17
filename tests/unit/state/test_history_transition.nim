## Published history STF transitions, independent accumulation trees and authored boundary/ordering tests.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../support/history_transition_fixture
import ../../../src/state/[history, store]
import ../../../src/codec/[state_layout, state_trie]

## Decode exact lowercase fixture bytes; malformed transport is a test failure, never protocol acceptance.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet = 0'u8
    assert parseHex(text[2*i..2*i+1], octet) == 2 # Every octet must be complete.
    result[i] = octet

## Preserve exact hash width when converting fixture identities to nominal domains.
proc hash(text: string): array[32, byte] =
  let bytes = unhex(text)
  assert bytes.len == 32
  result = default(array[32, byte])
  for i in 0..<32: result[i] = bytes[i] # Copied fixed identity without retained transport storage.

## Parse nonnegative fixture counts/slots without signed narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Separate finite complete-map budgets from the history component's own limits.
proc policy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(1000000),
      totalValueBytes: ByteLimit(2000000), nodes: TrieNodeLimit(498)),
      writes: ElementLimit(1), writeValueBytes: ByteLimit(1000000))

## Every supplied post-state is compared byte-for-byte; store integration preserves unrelated entries.
proc published(lines: seq[string]) =
  for i in 0..<8:
    let fields = lines[3*i].splitWhitespace() # Three transport lines per complete published case.
    let cores = int(number(fields[0]))
    let config = historyConfig(cores)
    let input = HistoryAdvance(slot: HistorySlot(uint32(number(fields[1]))),
        header: HistoryHeaderHash(hash(fields[2])), parentState: HistoryStateRoot(hash(fields[3])),
            accumulation: AccumulationRoot(hash(fields[4])))
    let count = int(number(fields[5]))
    assert fields.len == 6+count*2
    var packages = newSeq[ReportedPackage](count)
    for j in 0..<count:
      packages[j] = ReportedPackage(package: PackageHash(bytes: hash(fields[6+2*j])),
          segment: SegmentRoot(bytes: hash(fields[7+2*j]))) # Preserve each association from the vector.
    let before = unhex(lines[3*i+1])
    let after = unhex(lines[3*i+2])
    let decoded = decodeHistoryState(before, config)
    assert decoded.error == HistoryError.None and decoded.value.consumed == before.len
    let advanced = advanceHistory(decoded.value.snapshot, input, packages, config)
    assert advanced.error == HistoryTransitionError.None, "published advance rejected " &
        $advanced.error
    assert advanced.value.value == after, "published bytes"
    # Reversing guarantee/core order must produce the same canonical package dictionary.
    var reversed = newSeq[ReportedPackage](count)
    for j in 0..<count: reversed[j] = packages[count-1-j] # Preserve key/value association through reordering.
    assert advanceHistory(decoded.value.snapshot, input, reversed, config).value.value == after
    let original = @[StateEntry(key: chapterKey(StateChapter(3)), value: before),
        StateEntry(key: chapterKey(StateChapter(11)), value: @[99'u8])]
    let made = newStateStore(original, policy())
    assert made.error == StateStoreError.None
    var state = made.value
    let old = state.snapshot.value
    let committed = advanceHistoryState(state, input, packages, config)
    assert committed.error == HistoryTransitionError.None
    assert committed.value.lookup(original[0].key).value.bytes == after
    assert committed.value.lookup(original[1].key).value.bytes == @[99'u8]
    assert old.lookup(original[0].key).value.bytes == before
    let corrected = correctHistoryParent(decoded.value.snapshot, input.parentState, config)
    assert corrected.error == HistoryTransitionError.None
    let interim = decodeHistoryState(corrected.value.value, config).value.snapshot
    let info = historyInfo(interim).value
    if info.blocks > 0:
      assert array[32, byte](historyBlockAt(interim, HistoryBlockIndex(uint64(
          info.blocks-1))).value.state) == array[32, byte](input.parentState) # Parent visible to accumulation.
    assert advanceHistory(interim, input, packages, config).value.value == after,
        "repeat parent correction" # Repeated correction is idempotent.

## Compare the native well-balanced tree to a separate integer Keccak/equation oracle.
proc trees(lines: seq[string]) =
  for line in 24..<35:
    let fields = lines[line].splitWhitespace()
    let count = int(number(fields[0])) # Empty trees have no third transport field.
    let expected = hash(fields[1])
    let bytes = if count == 0: newSeq[byte](0) else: unhex(fields[2])
    assert bytes.len == count*36
    var values = newSeq[AccumulationOutput](count)
    for i in 0..<count:
      var service = 0'u32
      var commitment = default(array[32, byte])
      for j in 0..<4: service = service or (uint32(bytes[36*i+j]) shl (j*8)) # Exact E4 with high service IDs.
      for j in 0..<32: commitment[j] = bytes[36*i+4+j] # Raw leaf, not a prehashed commitment pair.
      values[i] = AccumulationOutput(service: ServiceIndex(service), commitment: OutputCommitment(commitment))
    let config = OutputLogConfig(items: ElementLimit(uint64(count)), maxBytes: ByteLimit(uint64(bytes.len+9)))
    let root = accumulationRoot(values, config)
    assert root.error == HistoryTransitionError.None and array[32, byte](root.value) == expected
    if count > 0:
      var tight = config
      tight.items = ElementLimit(uint64(count-1))
      assert accumulationRoot(values, tight).error ==
          HistoryTransitionError.LimitExceeded # Refuse work before hashing.

## Authored checks distinguish absent/present-zero peaks, maximum slots, budgets and malformed projections.
proc boundaries() =
  let config = historyConfig()
  var source = HistoryState(blocks: @[], peaks: @[absentHistoryPeak(), absentHistoryPeak()])
  let owner = historyOwner(source)
  source.peaks[0] = presentHistoryPeak(HistoryPeakHash(historyHash(99)))
  let input = HistoryAdvance(header: HistoryHeaderHash(historyHash(1)),
      parentState: HistoryStateRoot(historyHash(2)),

slot: HistorySlot(high(uint32)), accumulation: AccumulationRoot(default(array[32, byte])))
  let advanced = advanceHistory(owner, input, [], config)
  assert advanced.error == HistoryTransitionError.None
  let snapshot = decodeHistoryState(advanced.value.value, config).value.snapshot
  assert historyInfo(snapshot).value.peaks == 2 # Do not trim the untouched trailing hole.
  assert historyPeakAt(snapshot, HistoryPeakIndex(0)).value.present
  assert array[32, byte](historyPeakAt(snapshot, HistoryPeakIndex(0)).value.hash) == default(array[
      32, byte])
  assert not historyPeakAt(snapshot, HistoryPeakIndex(1)).value.present
  assert uint32(historyBlockAt(snapshot, HistoryBlockIndex(0)).value.slot) == uint32(input.slot)
  assert array[32, byte](historyBlockAt(snapshot, HistoryBlockIndex(0)).value.state) == default(
      array[32, byte])
  let package = ReportedPackage(package: PackageHash(bytes: historyHash(5)), segment: SegmentRoot(
      bytes: historyHash(7)))
  assert advanceHistory(owner, input, @[package, package], config).error ==
      HistoryTransitionError.NonCanonical
  assert advanceHistory(default(HistorySnapshot), input, [], config).error ==
      HistoryTransitionError.InvalidState
  var tight = config
  tight.blocks = ElementLimit(0)
  assert advanceHistory(owner, input, [], tight).error == HistoryTransitionError.LimitExceeded
  tight = config
  tight.peaks = ElementLimit(1)
  assert advanceHistory(owner, input, [], tight).error == HistoryTransitionError.LimitExceeded
  tight = config
  tight.maxBytes = ByteLimit(uint64(advanced.value.value.len-1))
  assert advanceHistory(owner, input, [], tight).error == HistoryTransitionError.LimitExceeded
  tight.maxBytes = ByteLimit(uint64(advanced.value.value.len))
  assert advanceHistory(owner, input, [], tight).value.value == advanced.value.value # Exact complete-byte policy.
  tight = config
  tight.cores = CoreCount(1)
  assert advanceHistory(owner, input, [], tight).error == HistoryTransitionError.InvalidConfig
  let empty = historyOwner(HistoryState(blocks: @[], peaks: @[]))
  tight = config
  tight.peaks = ElementLimit(0)
  assert advanceHistory(empty, input, [], tight).error ==
      HistoryTransitionError.LimitExceeded # First append needs one peak.
  # Three present peaks distinguish ascending left-fold bagging from reversed/right-fold variants.
  let multiple = historyOwner(HistoryState(blocks: @[], peaks: @[absentHistoryPeak(),
      presentHistoryPeak(HistoryPeakHash(historyHash(2))), absentHistoryPeak(),
      presentHistoryPeak(HistoryPeakHash(historyHash(3)))]))
  var bagInput = input
  bagInput.accumulation = AccumulationRoot(historyHash(1))
  let bagged = advanceHistory(multiple, bagInput, [], config)
  assert bagged.error == HistoryTransitionError.None
  let bagOwner = decodeHistoryState(bagged.value.value, config).value.snapshot
  assert array[32, byte](historyBlockAt(bagOwner, HistoryBlockIndex(0)).value.superPeak) ==
      hash("3bc014ffefbfc028b59bf796514dbba327d5d4685c6e3200734a1aeeb2ac8070") # Literal independent Keccak expectation using ASCII peak.
  # A 128-entry all-present belt exercises native bounded carry without a fixed bit-width cap.
  var peaks = newSeq[HistoryPeak](128)
  for i in 0..<peaks.len: peaks[i] = presentHistoryPeak(HistoryPeakHash(historyHash(byte(
      i)))) # Explicit present peaks.
  let full = historyOwner(HistoryState(blocks: @[], peaks: peaks))
  assert advanceHistory(full, input, [], config).error == HistoryTransitionError.LimitExceeded
  var broad = config
  broad.peaks = ElementLimit(129)
  assert historyInfo(decodeHistoryState(advanceHistory(full, input, [], broad).value.value,
      broad).value.snapshot).value.peaks == 129

var fixture = ""
try:
  fixture = readFile(getEnv("RAGNAROK_HISTORY_STF")) # Explicit I/O failure is a fixture error.
except:
  quit(2) # Never treat missing transport as successful protocol coverage.
let lines = fixture.splitLines()
assert lines.len == 36
trees(lines)
published(lines)
boundaries()
echo "PASS history transition: eight published STF cases, independent output trees and boundary/store contracts"
