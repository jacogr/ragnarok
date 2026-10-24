# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete selected-root entry streams lend canonical sorted values under fixed inherited IO and native pin ownership.
# @@Verification={"arc":"storage_full_paged_entries_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture]
import ../../../src/storage/[full_paged_codec, full_paged_stream, full_paged_store, paged_io,
  full_state_trie, node_records, file_errors]
import ../../../src/codec/[bounded, state_layout, state_trie]
type Capture = ref object ## Private consumer staging owns copies only; failed streams cannot expose a completed capture.
  keys: seq[StateKey]
  values: seq[seq[byte]]
  calls, stopAt: int
proc visitor(owner: Capture): FullPagedEntryVisitor =
  ## Caller-owned state remains outside the storage engine and can outlive native reader retirement.
  proc receive(ordinal: uint64, key: StateKey, value: openArray[byte]): bool {.closure.} =
    ## Every synchronous borrow receives its exact sorted ordinal and is copied before callback return.
    assert ordinal == uint64(owner.calls)
    inc owner.calls
    if owner.calls == owner.stopAt: return false
    var copied = newSeq[byte](value.len)
    for index in 0..<value.len: copied[index] = value[index] # No borrowed page/record storage escapes.
    owner.keys.add(key)
    owner.values.add(copied)
    true
  receive
proc path(label: string): string =
  ## Independent native namespaces keep tests isolated without scanning database directories.
  "full-paged-entries-" & $storageProcessId() & "-" & label
proc check(owner: Capture, value: byte) =
  ## Both complete values and serialized key order are independent of physical hash ordering.
  assert owner.calls == 2 and owner.keys.len == 2 and owner.values.len == 2
  assert array[31, byte](owner.keys[0]) == array[31, byte](key(0))
  assert array[31, byte](owner.keys[1]) == array[31, byte](key(128))
  assert owner.values[0] == @[value] and owner.values[1].len == 0
proc core(source: FullPagedFixture, root: StateRoot, value: byte, cache: int) =
  ## Independent retained maps, consumer refusal and every source callback failure exercise captured-root authority.
  let checked = source.check(policy(cache)).value
  let owner = Capture()
  source.io.calls = 0
  let streamed = streamFullPagedEntries(source.io.input, checked, root, owner.visitor, policy().work)
  assert streamed.error == FullPagedStreamError.None
  owner.check(value)
  let counters = streamed.value
  assert counters.writeBytes == 0 and counters.visits == 3
  let calls = source.io.calls
  for skip in 1..calls:
    # Every actually observed source read/extent refusal must prevent a successful whole-stream receipt.
    source.io.calls = 0
    source.io.failAt = skip
    let refused = streamFullPagedEntries(source.io.input, checked, root, Capture().visitor, policy().work)
    assert refused.error != FullPagedStreamError.None
  source.io.failAt = 0
  for stop in 1..2:
    let partial = Capture(stopAt: stop)
    let refused = streamFullPagedEntries(source.io.input, checked, root, partial.visitor, policy().work)
    assert refused.error == FullPagedStreamError.VisitorRefused and partial.calls == stop
  let exact = FullPagedWorkLimits(ioCalls: ElementLimit(counters.ioCalls), hashes: ElementLimit(
      counters.hashes),
    visits: ElementLimit(counters.visits), readBytes: ByteLimit(counters.readBytes),
        writeBytes: ByteLimit(0))
  assert streamFullPagedEntries(source.io.input, checked, root, Capture().visitor, exact).error ==
      FullPagedStreamError.None
  for channel in 0..<4:
    # Per-call work ceilings tighten captured policy; one-short IO/hash/visit/read ceilings all refuse.
    var short = exact
    case channel
    of 0: short.ioCalls = ElementLimit(counters.ioCalls-1)
    of 1: short.hashes = ElementLimit(counters.hashes-1)
    of 2: short.visits = ElementLimit(counters.visits-1)
    else: short.readBytes = ByteLimit(counters.readBytes-1)
    assert streamFullPagedEntries(source.io.input, checked, root, Capture().visitor, short).error ==
        FullPagedStreamError.LimitExceeded
  source.io.calls = 0
  var denied = exact
  denied.ioCalls = ElementLimit(0)
  let untouched = Capture()
  assert streamFullPagedEntries(source.io.input, checked, root, untouched.visitor, denied).error ==
      FullPagedStreamError.LimitExceeded
  assert untouched.calls == 0 and source.io.calls == 0
  source.io.calls = 0
  let unknown = Capture()
  assert streamFullPagedEntries(source.io.input, checked, default(StateRoot), unknown.visitor,
      exact).error == FullPagedStreamError.UnknownRoot
  assert unknown.calls == 0 and source.io.calls == 0
  assert streamFullPagedEntries(source.io.input, checked, root, nil, exact).error ==
      FullPagedStreamError.Uninitialized
  assert streamFullPagedEntries(source.io.input, default(CheckedFullPagedArtifact), root,
      owner.visitor, exact).error == FullPagedStreamError.Uninitialized
proc native(source: FullPagedFixture, old: StateRoot) =
  ## Native streaming creates no scratch, writer lease or retained callback and reports consumer refusal without poisoning the reader.
  let directory = path("native")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  writer.seed(directory, source)
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, source.config).error == FullPagedNativeError.None
  var info = reader.rootInfo(old).value
  assert info.entries == 2 and info.nodes == 3 and info.valueBytes == 1
  info.entries = 99
  assert reader.rootInfo(old).value.entries == 2
  assert reader.rootInfo(default(StateRoot)).graphError == FullPagedStreamError.UnknownRoot
  resetIo()
  let owner = Capture()
  assert reader.visitEntries(old, owner.visitor).error == FullPagedNativeError.None
  owner.check(5)
  assert ioCalls(readIo) > 0
  assert ioCalls(writeIo) == 0 and ioCalls(truncateIo) == 0 and ioCalls(closeIo) == 0
  let reads = ioCalls(readIo)
  for skip in 0..<int(reads):
    # Every native source read refusal prevents whole-root delivery while the independently held epoch stays immutable.
    resetIo()
    armIo(readIo, cint(skip), 1, failedIo)
    assert reader.visitEntries(old, Capture().visitor).error != FullPagedNativeError.None
    assert pendingIo() == 0
    resetIo()
    assert reader.close == FileError.None
    assert openFullPagedReader(reader, directory, source.config).error == FullPagedNativeError.None
  resetIo()
  let stopped = reader.visitEntries(old, Capture(stopAt: 1).visitor)
  assert stopped.error == FullPagedNativeError.GraphFailure
  assert stopped.graphError == FullPagedStreamError.VisitorRefused
  assert reader.lookup(old, key(0)).value.bytes[0] == 5
  assert reader.close == FileError.None
  owner.check(5)
  assert reader.visitEntries(old, Capture().visitor).error == FullPagedNativeError.Uninitialized
  assert reader.rootInfo(old).error == FullPagedNativeError.Uninitialized
proc cycle(reader: var FullPagedReader, root: StateRoot) =
  ## All consumer copies and callback state retire before the next ownership sample.
  let owner = Capture()
  assert reader.visitEntries(root, owner.visitor).error == FullPagedNativeError.None
  owner.check(5)
proc boundaryGraphs() =
  ## Empty maps, cross-page owned values and maximum-depth serialized keys cover all complete-root traversal shapes.
  let zero = default(TrieRecord)
  let empty = fixture(@[], zero, @[claim(zero, 0, 0, 0)])
  let checkedEmpty = empty.check(policy()).value
  let emptyOwner = Capture()
  let streamedEmpty = streamFullPagedEntries(empty.io.input, checkedEmpty, empty.header.root,
    emptyOwner.visitor, policy().work)
  assert streamedEmpty.error == FullPagedStreamError.None and streamedEmpty.value.visits == 0
  assert emptyOwner.calls == 0
  var value = newSeq[byte](4097)
  for index in 0..<value.len: value[index] = byte(index mod 251) # Independent cross-page payload pattern.
  let left = leaf(0, value)
  let right = leaf(128, @[])
  let parent = branch(left, right)
  let long = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, uint64(value.len))])
  let admitted = long.check(policy()).value
  let owner = Capture()
  assert streamFullPagedEntries(long.io.input, admitted, long.header.root, owner.visitor,
    policy().work).error == FullPagedStreamError.None
  assert owner.values[0] == value and owner.values[1].len == 0
  var a = default(array[31, byte])
  var b = a
  b[30] = 1
  var limits = policy()
  limits.work.ioCalls = ElementLimit(10000000)
  limits.work.hashes = ElementLimit(10000000)
  limits.work.readBytes = ByteLimit(1000000000)
  let trie = newFullStateTrie(@[StateEntry(key: StateKey(a), value: @[5'u8]),
    StateEntry(key: StateKey(b), value: @[])], FullStateTrieLimits(trie: limits.trie)).value
  let exported = trie.exportFullTrie(TrieExportLimits(records: TrieNodeLimit(1000),
    valueBytes: ByteLimit(1))).value
  assert exported.nodes == 250
  var root = default(TrieRecord)
  for record in exported.records:
    if array[32, byte](record.digest) == array[32, byte](exported.root): root = record # Exact full physical root.
  let deep = fixture(exported.records, root, @[claim(root, 2, 250, 1)])
  let checked = deep.check(limits).value
  let received = Capture()
  let streamed = streamFullPagedEntries(deep.io.input, checked, deep.header.root,
    received.visitor, limits.work)
  assert streamed.error == FullPagedStreamError.None and streamed.value.visits == 250
  assert received.calls == 2 and received.values[0] == @[5'u8] and received.values[1].len == 0
  assert array[31, byte](received.keys[0]) == a and array[31, byte](received.keys[1]) == b
proc main() =
  ## Complete historical roots remain distinct from the selected root; none of their physical ordinals become logical key order.
  let source = historySample(5, 9)
  let old = sample(5).header.root
  for cache in 0..1:
    core(source, old, 5, cache)
    core(source, source.header.root, 9, cache)
  native(source, old)
  boundaryGraphs()
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  writer.seed(directory, source)
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, source.config).error == FullPagedNativeError.None
  cycle(reader, old)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(reader, old) # A resident graph/index or retained visitor cannot hide across release cycles.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_entries", 1000, before, after)
  assert reader.close == FileError.None
  echo "storage full paged entries PASS"
main()
