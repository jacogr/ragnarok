# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete StateStore maps retain ordinary memory semantics across explicit paged transport, publication and restoration.
# @@Verification={"arc":"paged_state_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/state_full_paged_reference
import ../../support/state_full_paged_native_fixture
import ../../../src/state/store as state_store
import ../../../src/state/paged_state as state_paged_state
import ../../../src/storage/full_paged_codec as storage_full_paged_codec
import ../../../src/storage/full_paged_store as storage_full_paged_store
import ../../../src/storage/full_paged_build as storage_full_paged_build
import ../../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
func stateLimits(): StateStoreLimits =
  ## Full-map and mutation ceilings stay independent of native streaming/construction work.
  StateStoreLimits(trie: policy().trie, writes: ElementLimit(10), writeValueBytes: ByteLimit(10000))
func transportLimits(): PagedStateLimits =
  ## Root-input and aggregate staging quotas include shared records before physical deduplication.
  PagedStateLimits(roots: ElementLimit(64), staging: TrieExportLimits(records: TrieNodeLimit(1000),
    valueBytes: ByteLimit(100000)), dataset: policy().dataset)
proc state(value: byte): StateStore =
  ## An ordinary complete map supplies trusted immutable transport input, including a present-empty value.
  newStateStore(@[StateEntry(key: key(0), value: @[value]),
    StateEntry(key: key(128), value: @[])], stateLimits()).value
proc path(label: string): string =
  ## Caller-owned native namespaces are isolated without directory scans or implicit recovery.
  "paged-state-" & $storageProcessId() & "-" & label
proc check(snapshot: StateStoreSnapshot, value: byte) =
  ## Restored stores expose the exact existing sorted-key, empty-value and retained lookup contracts.
  assert snapshot.commitment.entries == 2
  assert snapshot.lookup(key(0)).value.bytes == @[value]
  assert snapshot.lookup(key(128)).value.bytes.len == 0
  assert array[31, byte](snapshot.keyAt(StateEntryIndex(0)).value) == array[31, byte](key(0))
  assert array[31, byte](snapshot.keyAt(StateEntryIndex(1)).value) == array[31, byte](key(128))
proc limitsAndCopies(source: StateStoreSnapshot) =
  ## Staging is bounded before export; mutable producer/claim outputs cannot alter opaque prepared backing.
  let prepared = preparePagedState(source, [], transportLimits()).value
  assert prepared.recordCount == 3
  var claims = prepared.roots
  claims[0].entries = 99
  assert prepared.roots[0].entries == 2
  let next = prepared.producer
  for ordinal in 0'u64..<prepared.recordCount:
    var record = default(TrieRecord)
    assert next(0, ordinal, record) == FullPagedProducerStep.Item
    if record.kind == TrieRecordKind.Leaf and record.payload.len > 0:
      record.payload[0] = 99 # Mutate an independently owned public producer result.
      var again = default(TrieRecord)
      assert next(1, ordinal, again) == FullPagedProducerStep.Item
      assert again.payload[0] == 5
  var short = transportLimits()
  short.staging.records = TrieNodeLimit(2)
  assert preparePagedState(source, [], short).error == PagedStateError.LimitExceeded
  short = transportLimits()
  short.staging.valueBytes = ByteLimit(0)
  assert preparePagedState(source, [], short).error == PagedStateError.LimitExceeded
  short = transportLimits()
  short.dataset.bytes = ByteLimit(prepared.byteLength-1)
  assert preparePagedState(source, [], short).error == PagedStateError.GeometryFailure
  short.dataset.bytes = ByteLimit(prepared.byteLength)
  assert preparePagedState(source, [], short).error == PagedStateError.None
  let repeated = preparePagedState(source, [source], transportLimits()).value
  assert repeated.recordCount == 3 and repeated.roots.len == 1
  short = transportLimits()
  short.staging.valueBytes = ByteLimit(1)
  assert preparePagedState(source, [source], short).error == PagedStateError.LimitExceeded
  assert preparePagedState(default(StateStoreSnapshot), [], short).error ==
      PagedStateError.StateFailure
  var other = stateLimits()
  other.writes = ElementLimit(9)
  let different = newStateStore([], other).value.snapshot.value
  assert preparePagedState(source, [different], transportLimits()).error ==
      PagedStateError.PolicyMismatch
proc normal(source: StateStoreSnapshot) =
  ## Private memory updates and complete root unions publish only through the ordinary explicit native protocol.
  let directory = path("normal")
  let prepared = preparePagedState(source, [], transportLimits()).value
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  var old = default(FullPagedReader)
  var reader = default(FullPagedReader)
  defer:
    if reader.opened: discard reader.close # Every test-owned native obligation remains explicit.
    if old.opened: discard old.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  let config = sample(5).config
  var wrong = config
  wrong.root = sample(9).header.root
  resetIo()
  assert initializePagedStateStore(writer, directory, wrong, prepared).error ==
      PagedStateError.RootMismatch
  assert ioCalls(writeIo) == 0 and not writer.opened
  let initial = initializePagedStateStore(writer, directory, config, prepared)
  assert initial.error == PagedStateError.None and initial.value.writerUsable
  let before = writer.selected.value
  assert openFullPagedReader(old, directory, config).error == FullPagedNativeError.None
  var working = forkStateStore(source).value
  let target = working.apply([StateWrite(key: key(0), kind: StateWriteKind.Put, value: @[9'u8])]).value
  let union = preparePagedState(target, [source], transportLimits()).value
  assert union.recordCount == 5 and union.roots.len == 2
  assert preparePagedStateReplacement(writer, candidate, default(FullPagedManifest), union).error ==
      PagedStateError.StaleView
  assert preparePagedStateReplacement(writer, candidate, before, union).error ==
      PagedStateError.None
  let published = writer.publish(candidate)
  assert published.error == FullPagedNativeError.None
  assert uint64(published.value.manifest.generation) == 1
  assert preparePagedStateReplacement(writer, candidate, before, union).error ==
      PagedStateError.StaleView
  source.check(5)
  target.check(9)
  var selected = config
  selected.root = target.commitment.root
  assert openFullPagedReader(reader, directory, selected).error == FullPagedNativeError.None
  let restored = restorePagedStateStore(reader, target.commitment.root, stateLimits())
  assert restored.error == PagedStateError.None
  let current = restored.value.snapshot.value
  current.check(9)
  restorePagedStateStore(reader, source.commitment.root, stateLimits()).value.snapshot.value.check(5)
  assert restorePagedStateStore(reader, default(StateRoot), stateLimits()).error ==
      PagedStateError.NativeFailure
  var narrow = stateLimits()
  narrow.trie.items = ElementLimit(1)
  resetIo()
  assert restorePagedStateStore(reader, target.commitment.root, narrow).error ==
      PagedStateError.LimitExceeded
  assert ioCalls(readIo) == 0
  narrow = stateLimits()
  narrow.trie.perValue = ByteLimit(0)
  let refused = restorePagedStateStore(reader, target.commitment.root, narrow)
  assert refused.error == PagedStateError.StateFailure and refused.stateError ==
      StateStoreError.LimitExceeded
  assert reader.lookup(target.commitment.root, key(0)).value.bytes[0] == 9
  assert reader.close == FileError.None and old.close == FileError.None and writer.close == FileError.None
  current.check(9)
  source.check(5)
proc emptyWithHistory(source: StateStoreSnapshot) =
  ## Selecting an empty map while retaining nonempty history must not restore unrelated physical leaves.
  let directory = path("empty")
  let empty = newStateStore([], stateLimits()).value.snapshot.value
  let prepared = preparePagedState(empty, [source], transportLimits()).value
  var config = sample(5).config
  config.root = empty.commitment.root
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  assert initializePagedStateStore(writer, directory, config, prepared).error ==
      PagedStateError.None
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  let restored = restorePagedStateStore(reader, empty.commitment.root, stateLimits())
  assert restored.error == PagedStateError.None and
      restored.value.snapshot.value.commitment.entries == 0
  restorePagedStateStore(reader, source.commitment.root, stateLimits()).value.snapshot.value.check(5)
  assert reader.close == FileError.None
proc closeDiagnostics(prepared: PreparedPagedState) =
  ## Composite initialization must never erase an already confirmed native receipt after retirement uncertainty.
  var count = 0'u64
  var confirmed = 0
  for skip in -1..<100:
    if skip < 0 or uint64(skip) < count:
      let directory = path("close-" & $skip)
      var writer = default(FullPagedWriter)
      resetIo()
      if skip >= 0: armIo(closeIo, cint(skip), 1, failedIo) # Only the previously observed close schedule is injected.
      let outcome = initializePagedStateStore(writer, directory, sample(5).config, prepared)
      if skip < 0:
        assert outcome.error == PagedStateError.None
        count = ioCalls(closeIo)
        assert count > 0 and count < 100
      else:
        assert pendingIo() == 0
        if outcome.error == PagedStateError.None:
          assert outcome.value.retirementError == FileError.IoFailure
          inc confirmed
        else:
          assert outcome.error == PagedStateError.NativeFailure
          assert outcome.nativeFailure.error != FullPagedNativeError.None
      resetIo()
      if writer.opened: assert writer.close == FileError.None
  assert confirmed > 0
proc readFailures(prepared: PreparedPagedState) =
  ## Every observed consumer read failure exposes no partially restored StateStore; a fresh owner recovers normally.
  let directory = path("reads")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  let config = sample(5).config
  assert initializePagedStateStore(writer, directory, config, prepared).error ==
      PagedStateError.None
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  resetIo()
  assert restorePagedStateStore(reader, prepared.root, stateLimits()).error == PagedStateError.None
  let reads = ioCalls(readIo)
  for skip in 0..<int(reads):
    resetIo()
    armIo(readIo, cint(skip), 1, failedIo)
    assert restorePagedStateStore(reader, prepared.root, stateLimits()).error ==
        PagedStateError.NativeFailure
    assert pendingIo() == 0
    resetIo()
    assert reader.close == FileError.None
    assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  assert reader.close == FileError.None
proc cycle(reader: var FullPagedReader, source: StateStoreSnapshot) =
  ## All transport records, callbacks, ordinary reconstructed maps and temporary exports retire before sampling.
  let prepared = preparePagedState(source, [source], transportLimits()).value
  assert prepared.recordCount == 3
  restorePagedStateStore(reader, source.commitment.root, stateLimits()).value.snapshot.value.check(5)
proc main() =
  ## New transport preserves complete-map roots, policy, history, independent forks and explicit native ownership.
  let source = state(5).snapshot.value
  limitsAndCopies(source)
  normal(source)
  emptyWithHistory(source)
  let prepared = preparePagedState(source, [], transportLimits()).value
  closeDiagnostics(prepared)
  readFailures(prepared)
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  assert initializePagedStateStore(writer, directory, sample(5).config, prepared).error ==
      PagedStateError.None
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, sample(5).config).error == FullPagedNativeError.None
  cycle(reader, source)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(reader, source) # Resident consumer copies remain separate from native working-set qualification.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_state", 1000, before, after)
  assert reader.close == FileError.None
  echo "paged state PASS"
main()
