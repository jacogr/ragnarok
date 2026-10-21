# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Correctness-validated equal physical-repository workloads compare memory, synced journal and managed IO.
import std/[assertions, syncio, cmdline, monotimes, times]
import std/posix/posix
import ../support/managed_storage_samples
import ../../src/storage/[full_state_trie, node_repository, node_records, record_codec,
  file_repository, managed_repository, database_identity, managed_manifest]
import ../../src/codec/[bounded, state_layout, state_trie]

proc key(index: int): StateKey =
  ## Fixed authored keys are sorted by the first two bytes and fit the complete key domain.
  assert index >= 0 and index < 65536
  var raw = default(array[31, byte])
  raw[0] = byte(index shr 8)
  raw[1] = byte(index and 255)
  StateKey(raw)
proc value(index, applied: int): seq[byte] =
  ## Every fixture has 256-byte values, with sixteen distinct single-key successor updates.
  result = newSeq[byte](256)
  let octet = if index < applied: byte(index+1) else: byte(index and 255)
  for position in 0..<256:
    result[position] = octet # Full payload checks follow every timed operation group.
proc check(view: RepositoryView, trie: StateTrieLimits, count: int, expected: StateRoot) =
  ## Independently authored keys/values and the sealed fixture root must match after publication/reopen.
  assert array[32, byte](view.commitment.root) == array[32, byte](expected)
  assert uint64(view.generation) == 17
  let entries = restoreStateEntries(view, expected, trie).value
  assert entries.len == count
  for index, entry in entries:
    assert array[31, byte](entry.key) == array[31, byte](key(index))
    assert entry.value == value(index, 16)
proc elapsed(start: MonoTime): int64 =
  ## Monotonic positive nanoseconds describe one fixed public API operation batch.
  (getMonoTime()-start).inNanoseconds
proc main() {.raises.} =
  ## Python selects only explicit engines/sizes and supplies one isolated owned directory per pass.
  assert paramCount() == 3
  let engine = paramStr(1)
  assert engine in ["memory", "journal", "managed"]
  let countText = paramStr(2)
  assert countText in ["1024", "8192"]
  let count = if countText == "1024": 1024 else: 8192
  let folder = paramStr(3)
  let trie = StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(2097152), nodes: TrieNodeLimit(100000))
  let limits = RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(4194304)),
    encoded: ByteLimit(16777216)), records: ElementLimit(200000), valueBytes: ByteLimit(8388608))
  let journal = JournalLimits(repository: limits, bytes: ByteLimit(33554432))
  let managed = ManagedLimits(repository: limits, roots: ElementLimit(9),
    snapshotBytes: ByteLimit(33554432), journalBytes: ByteLimit(33554432), contextBytes: ByteLimit(64))
  var entries: seq[StateEntry] = @[]
  for index in 0..<count:
    entries.add(StateEntry(key: key(index), value: value(index, 0)))
  var state = newFullStateTrie(entries, FullStateTrieLimits(trie: trie,
    writes: ElementLimit(1), writeValueBytes: ByteLimit(256))).value
  let full = exportFullTrie(state, limits.codec.records).value
  var reads: seq[StateNodeHash] = @[]
  for record in full.records:
    if record.kind == TrieRecordKind.Leaf:
      let raw = array[31, byte](record.key)
      let number = int(raw[0])*256+int(raw[1])
      if number >= count-128:
        reads.add(record.digest) # The final 128 leaves remain unchanged by the sixteen updates.
  assert reads.len == 128
  var changes: seq[TrieExport] = @[]
  for index in 0..<16:
    let next = state.apply([TrieWrite(key: key(index), kind: TrieWriteKind.Put,
      value: value(index, index+1))]).value
    changes.add(exportTrieChanges(state, next, limits.codec.records).value)
    state = next # Preparation, Merklization and fixture construction stay outside timed publication.
  let expected = state.commitment.root
  var seed = newNodeRepository(limits)
  let seedView = seed.publish(seed.snapshot.value, full).value
  let selection = selectRepositoryRoots(seedView, [seedView.commitment.root], ElementLimit(1)).value
  for sample in 0..<13:
    # Three validated warmups precede ten measured samples, each with a fresh repository namespace.
    let path = folder & "/sample-" & $sample
    var memory = newNodeRepository(limits)
    var disk = default(FileRepository)
    defer:
      if disk.opened:
        discard disk.close # IO exceptions must still release the exclusive directory/file owner.
    if engine == "memory":
      discard memory.publish(memory.snapshot.value, full).value
    elif engine == "journal":
      assert initializeFileRepository(disk, path, default(StorageChainId), journal) == FileError.None
      discard disk.publish(disk.snapshot.value, full).value
    else:
      assert initializeManagedFileRepository(disk, path, default(StorageChainId), selection, [],
          managed) == FileError.None
    let publicationStart = getMonoTime()
    for index in 0..<changes.len:
      if engine == "memory":
        discard memory.publish(memory.snapshot.value, changes[index]).value
      else:
        discard disk.publish(disk.snapshot.value, changes[
            index]).value # Real disk publication includes its synchronization barrier.
    let publicationNs = elapsed(publicationStart)
    let view = if engine == "memory": memory.snapshot.value else: disk.snapshot.value
    check(view, trie, count, expected)
    var observed = newSeq[TrieRecord](4096)
    let readStart = getMonoTime()
    for index in 0..<observed.len:
      observed[index] = view.lookupNode(reads[index mod 128]).value
    let readNs = elapsed(readStart)
    for index, record in observed:
      assert record.kind == TrieRecordKind.Leaf
      assert array[32, byte](record.digest) == array[32, byte](reads[index mod 128])
      let raw = array[31, byte](record.key)
      let number = int(raw[0])*256+int(raw[1])
      assert number >= count-128 and number < count
      assert record.payload == value(number, 16) # Validate every returned byte outside the measured read interval.
    let extractStart = getMonoTime()
    let restored = restoreStateEntries(view, expected, trie).value
    let extractNs = elapsed(extractStart)
    assert restored.len == count
    for index, entry in restored:
      assert array[31, byte](entry.key) == array[31, byte](key(index))
      assert entry.value == value(index, 16)
    var reopenNs = -1'i64
    if engine != "memory":
      assert disk.close == FileError.None
      let reopenStart = getMonoTime()
      if engine == "journal":
        assert openFileRepository(disk, path, default(StorageChainId), journal) == FileError.None
      else:
        assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
      reopenNs = elapsed(reopenStart)
      check(disk.snapshot.value, trie, count, expected)
      assert disk.close == FileError.None
      if engine == "journal":
        var nativePath = path
        assert posix.unlink(nativePath.toCString()) == 0
      else:
        removeManagedSample(path, [ManagedEpoch(1)]) # Cleanup covers only this fixture's exact known epoch.
    assert memory.close == RepositoryError.None
    echo "sample\t", count, "\t", sample, "\t", publicationNs, "\t", readNs, "\t", extractNs, "\t", reopenNs
  assert seed.close == RepositoryError.None
try:
  main()
except:
  quit(2)
