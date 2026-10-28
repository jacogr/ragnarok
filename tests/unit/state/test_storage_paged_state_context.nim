# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Contextual local restart restores independently recomputed complete maps under one exclusive writer lease.
# @@Verification={"arc":"paged_state_context_arc_release"}
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
import ../../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../../src/storage/full_paged_build as storage_full_paged_build
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
func statePolicy(): StateStoreLimits =
  ## Ordinary immutable map policy remains independent of paged context and physical IO work.
  StateStoreLimits(trie: policy().trie, writes: ElementLimit(10), writeValueBytes: ByteLimit(10000))
func transportPolicy(): PagedStateLimits =
  ## Aggregate export counts all retained complete snapshots before physical record deduplication.
  PagedStateLimits(roots: ElementLimit(64), staging: TrieExportLimits(records: TrieNodeLimit(1000),
    valueBytes: ByteLimit(100000)), dataset: policy().dataset)
proc state(first: byte): StateStoreSnapshot =
  ## Independently constructed complete maps include a present-empty value.
  newStateStore(@[StateEntry(key: key(0), value: @[first]), StateEntry(key: key(128), value: @[])],
    statePolicy()).value.snapshot.value
proc path(label: string): string =
  ## Each test owns its namespace under the native runner's ignored directory.
  "paged-state-context-" & $storageProcessId() & "-" & label
proc configuration(first: byte): FullPagedNativeConfig =
  ## Native and application input policies retain explicit independent finite ceilings.
  result = sample(first).config
  result.limits.contextBytes = ByteLimit(8192)
proc localOpen(writer: var FullPagedWriter, directory: string,
    selected: FullPagedNativeConfig): FullPagedNativeResult[bool] =
  ## The local API accepts chain and policy, deliberately requiring no independently imported root.
  openLocalFullPagedWriter(writer, directory, selected.chain, selected.limits,
    selected.construction, selected.replayBytes)
proc check(writer: FullPagedWriter, expected: StateStoreSnapshot, value: byte) =
  ## Native claims only preflight size; the existing state constructor recomputes every complete JAM root.
  let restored = restorePagedStateStore(writer, expected.commitment.root, statePolicy())
  assert restored.error == PagedStateError.None
  let snapshot = restored.value.snapshot.value
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](expected.commitment.root)
  assert snapshot.lookup(key(0)).value.bytes == @[value]
  assert snapshot.lookup(key(128)).value.bytes.len == 0
proc main() =
  ## Local recovery never weakens independently expected opens, failure quarantine or ordinary owned snapshot semantics.
  let source = state(5)
  let target = state(9)
  let prepared = preparePagedState(source, [], transportPolicy()).value
  let union = preparePagedState(target, [source], transportPolicy()).value
  let selected = configuration(5)
  var context = newSeq[byte](4097)
  context[0] = 7
  context[4096] = 9
  let directory = path("normal")
  var writer = default(FullPagedWriter)
  var competing = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  var candidate = default(FullPagedCandidate)
  defer:
    # Every path releases explicit native retirement obligations, including poisoned or failed authoring owners.
    resetIo()
    if candidate.opened: discard candidate.close
    if reader.opened: discard reader.close
    if competing.opened: discard competing.close
    if writer.opened: discard writer.close
  let initialized = initializePagedStateStore(writer, directory, selected, prepared, context)
  assert initialized.error == PagedStateError.None and initialized.value.writerUsable
  assert writer.readContext(selected.limits.work).value.bytes == context
  assert writer.localOpen(directory, selected).fileError == FileError.Busy
  assert competing.localOpen(directory, selected).fileError == FileError.Busy
  assert not competing.opened
  check(writer, source, 5)
  let first = writer.selected.value
  let publishedContext = @[11'u8, 12, 13]
  assert preparePagedStateReplacement(writer, candidate, first, union, publishedContext).error ==
      PagedStateError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert uint64(writer.selected.value.generation) == 1
  assert writer.readContext(selected.limits.work).value.bytes == publishedContext
  check(writer, source, 5)
  check(writer, target, 9)
  let retained = restorePagedStateStore(writer, target.commitment.root, statePolicy()).value.snapshot.value
  assert writer.close == FileError.None
  assert retained.lookup(key(0)).value.bytes == @[9'u8]
  let wrong = openFullPagedWriter(writer, directory, selected)
  assert wrong.error != FullPagedNativeError.None and not writer.opened
  assert writer.localOpen(directory, selected).error == FullPagedNativeError.None
  assert array[32, byte](writer.selected.value.root) == array[32, byte](target.commitment.root)
  assert writer.readContext(selected.limits.work).value.bytes == publishedContext
  check(writer, source, 5)
  check(writer, target, 9)
  var tooSmall = statePolicy()
  tooSmall.trie.items = ElementLimit(1)
  assert restorePagedStateStore(writer, target.commitment.root, tooSmall).error ==
      PagedStateError.LimitExceeded
  assert restorePagedStateStore(writer, default(StateRoot), statePolicy()).error ==
      PagedStateError.NativeFailure
  assert writer.close == FileError.None
  var wrongChain = selected
  var chain = array[32, byte](wrongChain.chain)
  chain[0] = 1
  wrongChain.chain = StorageChainId(chain)
  assert writer.localOpen(directory, wrongChain).error == FullPagedNativeError.CodecFailure
  assert not writer.opened
  var noContext = selected
  noContext.limits.contextBytes = ByteLimit(0)
  let unsupported = writer.localOpen(directory, noContext)
  assert unsupported.error == FullPagedNativeError.GraphFailure
  assert unsupported.graphError == FullPagedStreamError.UnsupportedPolicy and not writer.opened
  assert writer.localOpen(directory, selected).error == FullPagedNativeError.None
  resetIo()
  check(writer, target, 9)
  let calls = ioCalls(readIo)
  assert calls > 0 and calls <= uint64(high(cint))
  for skip in 0..<int(calls):
    # A failed private graph/value prefix cannot yield any complete StateStore; fresh lease admission is explicit.
    armIo(readIo, cint(skip), 1, failedIo)
    let failed = restorePagedStateStore(writer, target.commitment.root, statePolicy())
    assert failed.error == PagedStateError.NativeFailure and pendingIo() == 0
    resetIo()
    assert writer.close == FileError.None
    assert writer.localOpen(directory, selected).error == FullPagedNativeError.None
  check(writer, target, 9)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Repeated owned complete maps and context getters release before the next measured cycle.
    check(writer, target, 9)
    assert writer.readContext(selected.limits.work).value.bytes == publishedContext
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_state_context", 1000, before, after)
  assert writer.close == FileError.None
  assert restorePagedStateStore(writer, target.commitment.root, statePolicy()).error ==
      PagedStateError.NativeFailure
  echo "paged state context PASS"
main()
