# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Correctness-validated equal physical-repository workloads compare memory, synced journal and managed IO.
import std/[assertions, syncio, cmdline, monotimes, times]
import std/posix/posix
import ../support/managed_storage_samples
import ../../src/storage/[full_state_trie, node_repository, node_records, record_codec,
  file_repository, managed_repository, database_identity, managed_manifest]
import ../../src/codec/[bounded, state_layout, state_trie]

proc key(index: int, deep: bool): StateKey =
  ## Authored leading/trailing two-byte identities distinguish short and very deep common key prefixes.
  assert index >= 0 and index < 65536
  var raw = default(array[31, byte])
  let offset = if deep: 29 else: 0
  raw[offset] = byte(index shr 8)
  raw[offset+1] = byte(index and 255)
  StateKey(raw)
proc value(index, applied, valueBytes: int): seq[byte] =
  ## Inline and out-of-line payload sizes use the same sixteen deterministic successor updates.
  result = newSeq[byte](valueBytes)
  let octet = if index < applied: byte(index+1) else: byte(index and 255)
  for position in 0..<valueBytes:
    result[position] = octet # Full payload checks follow every timed operation group.
proc check(view: RepositoryView, trie: StateTrieLimits, count: int, expected: StateRoot, deep: bool,
    valueBytes: int) =
  ## Independently authored keys/values and the sealed fixture root must match after publication/reopen.
  assert array[32, byte](view.commitment.root) == array[32, byte](expected)
  assert uint64(view.generation) == 17
  let entries = restoreStateEntries(view, expected, trie).value
  assert entries.len == count
  for index, entry in entries:
    assert array[31, byte](entry.key) == array[31, byte](key(index, deep))
    assert entry.value == value(index, 16, valueBytes)
proc checkHistory(view: RepositoryView, trie: StateTrieLimits, count: int,
    roots: openArray[StateRoot], deep: bool, valueBytes: int) =
  ## Nine authored complete historical maps remain distinct from block finality or checkpoint authority.
  assert roots.len == 9
  for revision, root in roots:
    let entries = restoreHistoricalStateEntries(view, root, trie).value
    let applied = if revision == 0: 0 else: revision+8
    assert entries.len == count
    for index, entry in entries:
      assert array[31, byte](entry.key) == array[31, byte](key(index, deep))
      assert entry.value == value(index, applied, valueBytes)
proc elapsed(start: MonoTime): int64 =
  ## Monotonic positive nanoseconds describe one fixed public API operation batch.
  (getMonoTime()-start).inNanoseconds
proc main() {.raises.} =
  ## Python selects only explicit engines/sizes and supplies one isolated owned directory per pass.
  assert paramCount() == 5
  let engine = paramStr(1)
  assert engine in ["memory", "journal", "managed"]
  let countText = paramStr(2)
  assert countText in ["1024", "8192"]
  let count = if countText == "1024": 1024 else: 8192
  let folder = paramStr(3)
  let topology = paramStr(4)
  assert topology in ["leading", "trailing"]
  let deep = topology == "trailing"
  let valueText = paramStr(5)
  assert valueText in ["16", "256"]
  let valueBytes = if valueText == "16": 16 else: 256
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
    entries.add(StateEntry(key: key(index, deep), value: value(index, 0, valueBytes)))
  var state = newFullStateTrie(entries, FullStateTrieLimits(trie: trie,
    writes: ElementLimit(1), writeValueBytes: ByteLimit(256))).value
  let full = exportFullTrie(state, limits.codec.records).value
  var reads: seq[StateNodeHash] = @[]
  for record in full.records:
    if record.kind == TrieRecordKind.Leaf:
      let raw = array[31, byte](record.key)
      let number = int(raw[if deep: 29 else: 0])*256+int(raw[if deep: 30 else: 1])
      if number >= count-128:
        reads.add(record.digest) # The final 128 leaves remain unchanged by the sixteen updates.
  assert reads.len == 128
  var changes: seq[TrieExport] = @[]
  for index in 0..<16:
    let next = state.apply([TrieWrite(key: key(index, deep), kind: TrieWriteKind.Put,
      value: value(index, index+1, valueBytes))]).value
    changes.add(exportTrieChanges(state, next, limits.codec.records).value)
    state = next # Preparation, Merklization and fixture construction stay outside timed publication.
  var roots: seq[StateRoot] = @[full.root]
  for index in 8..<16:
    roots.add(changes[index].root) # Root preparation and all historical expectations remain outside timing.
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
    check(view, trie, count, expected, deep, valueBytes)
    var observed = newSeq[TrieRecord](4096)
    let readStart = getMonoTime()
    for index in 0..<observed.len:
      observed[index] = view.lookupNode(reads[index mod 128]).value
    let readNs = elapsed(readStart)
    for index, record in observed:
      assert record.kind == TrieRecordKind.Leaf
      assert array[32, byte](record.digest) == array[32, byte](reads[index mod 128])
      let raw = array[31, byte](record.key)
      let number = int(raw[if deep: 29 else: 0])*256+int(raw[if deep: 30 else: 1])
      assert number >= count-128 and number < count
      assert record.payload == value(number, 16, valueBytes) # Validate every returned byte outside the measured read interval.
    let extractStart = getMonoTime()
    let restored = restoreStateEntries(view, expected, trie).value
    let extractNs = elapsed(extractStart)
    assert restored.len == count
    for index, entry in restored:
      assert array[31, byte](entry.key) == array[31, byte](key(index, deep))
      assert entry.value == value(index, 16, valueBytes)
    var reopenNs = -1'i64
    if engine != "memory":
      assert disk.close == FileError.None
      let reopenStart = getMonoTime()
      if engine == "journal":
        assert openFileRepository(disk, path, default(StorageChainId), journal) == FileError.None
      else:
        assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
      reopenNs = elapsed(reopenStart)
      check(disk.snapshot.value, trie, count, expected, deep, valueBytes)
    let storedNodes = view.storedNodes
    let selectedNodes = selectRepositoryRoots(view, [expected], ElementLimit(1)).value.retainedNodes
    var snapshotBytes = -1'i64
    var journalBytes = -1'i64
    var compactedSnapshotBytes = -1'i64
    var compactedJournalBytes = -1'i64
    if engine == "journal":
      snapshotBytes = 0 # The legacy layout has no selected snapshot file.
      journalBytes = int64(readFile(path).len)
    elif engine == "managed":
      let usage = disk.managedUsage.value
      assert usage.snapshotBytes <= uint64(high(int64)) and usage.journalBytes <= uint64(high(int64))
      snapshotBytes = int64(usage.snapshotBytes)
      journalBytes = int64(usage.journalBytes)
    var retentionNs = -1'i64
    if engine == "memory":
      # Clone the same nine complete roots into an independent owner without durability claims.
      let retentionStart = getMonoTime()
      let retained = selectRepositoryRoots(view, roots, ElementLimit(9)).value
      var cloned = cloneRepositorySelection(retained, limits).value
      retentionNs = elapsed(retentionStart)
      checkHistory(cloned.snapshot.value, trie, count, roots, deep, valueBytes)
      assert memory.close == RepositoryError.None
      memory = cloned # Subsequent current-only reclamation starts from the same nine-root union as managed IO.
      assert cloned.close == RepositoryError.None
    elif engine == "managed":
      # Keep eight recent roots plus the seed before measuring current-only reclamation separately.
      let retentionStart = getMonoTime()
      let receipt = disk.compact(disk.snapshot.value, roots).value
      retentionNs = elapsed(retentionStart)
      assert receipt.cleanup == FileError.None and uint64(receipt.epoch) == 2
      checkHistory(disk.snapshot.value, trie, count, roots, deep, valueBytes)
      assert disk.close == FileError.None
      assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
      checkHistory(disk.snapshot.value, trie, count, roots, deep, valueBytes)
    var maintenanceNs = -1'i64
    if engine == "memory":
      # Compare current-root reclamation through an independent private clone, without claiming durability.
      let maintenanceStart = getMonoTime()
      let retained = selectRepositoryRoots(memory.snapshot.value, [expected], ElementLimit(1)).value
      var cloned = cloneRepositorySelection(retained, limits).value
      maintenanceNs = elapsed(maintenanceStart)
      check(cloned.snapshot.value, trie, count, expected, deep, valueBytes)
      assert cloned.snapshot.value.storedNodes < view.storedNodes
      assert cloned.close == RepositoryError.None
    elif engine == "managed":
      # Managed replacement includes the actual file/namespace barriers and predecessor retirement.
      let maintenanceStart = getMonoTime()
      let receipt = disk.compact(disk.snapshot.value, [expected]).value
      maintenanceNs = elapsed(maintenanceStart)
      assert receipt.cleanup == FileError.None and uint64(receipt.epoch) == 3
      assert receipt.reclaimedNodes > 0
      check(disk.snapshot.value, trie, count, expected, deep, valueBytes)
      assert disk.managedUsage.value.journalBytes == uint64(ManagedJournalHeaderBytes)
      assert disk.close == FileError.None
      assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
      check(disk.snapshot.value, trie, count, expected, deep, valueBytes)
    if engine == "managed":
      let usage = disk.managedUsage.value
      assert usage.storedNodes == selectedNodes
      assert usage.snapshotBytes <= uint64(high(int64)) and usage.journalBytes <= uint64(high(int64))
      compactedSnapshotBytes = int64(usage.snapshotBytes)
      compactedJournalBytes = int64(usage.journalBytes)
    check(view, trie, count, expected, deep, valueBytes) # Held maps survive physical retirement and private clone close.
    if disk.opened:
      assert disk.close == FileError.None
      if engine == "journal":
        var nativePath = path
        assert posix.unlink(nativePath.toCString()) == 0
      else:
        removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
    assert memory.close == RepositoryError.None
    echo "sample\t", count, "\t", topology, "\t", valueBytes, "\t", sample, "\t", publicationNs,
        "\t", readNs, "\t", extractNs, "\t", reopenNs, "\t", maintenanceNs, "\t", retentionNs, "\t",
            storedNodes, "\t", selectedNodes, "\t", snapshotBytes,
        "\t", journalBytes, "\t", compactedSnapshotBytes, "\t", compactedJournalBytes
  assert seed.close == RepositoryError.None
try:
  main()
except:
  quit(2)
