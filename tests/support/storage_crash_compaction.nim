# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed replacement process death preserves one complete selected epoch and independent held readers.
import std/assertions
import std/syncio
import ./storage_samples
import ./app_managed_storage_samples
import ./storage_io
import ./storage_crash
import ./storage_crash_appends
import ./storage_bootstrap_faults
import ../../src/storage/full_state_trie as storage_full_state_trie
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/file_repository as storage_file_repository
import ../../src/storage/managed_repository as storage_managed_repository
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/snapshot_codec as storage_snapshot_codec
import ../../src/storage/database_identity as storage_database_identity
import ../../src/codec/bounded as codec_bounded
proc compactionCrashCase*(label: string, operation, skip: cint,
    shortWrites = false, retainedContext = false): uint64 {.raises.} =
  ## Prepare a complete obsolete root, then observe only physical compaction after the child's strict open.
  resetIo()
  let path = label & "-" & $operation & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let schema = if retainedContext: StorageSchema.FullStateV1 else: StorageSchema.FullNodesV1
  let beforeContext: seq[byte] = if retainedContext: @[1'u8, 2, 3] else: @[]
  let afterContext: seq[byte] = if retainedContext: @[9'u8, 0, 8, 7] else: @[]
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    abortCrash()
    resetIo()
    if file.opened: discard file.close
  assert initializeManagedFileRepository(file, path, default(StorageChainId), selection,
      beforeContext, limits, schema) == FileError.None
  let held = file.snapshot.value
  let heldContext = file.snapshotContext.value
  assert heldContext == beforeContext
  let current = file.publish(held, exportTrieChanges(a, b,
      limits.repository.codec.records).value, afterContext).value
  let roots = if retainedContext: @[held.commitment.root, current.commitment.root] else: @[
      current.commitment.root]
  let plan = selectRepositoryRoots(current, roots, limits.roots).value
  let encoded = encodeRepositorySnapshot(plan, default(StorageChainId), schema, afterContext, SnapshotLimits(repository: limits.repository, roots: limits.roots,
          context: limits.contextBytes, bytes: limits.snapshotBytes)).value
  let manifest = encodeManagedManifest(default(StorageChainId), schema,
      ManagedEpoch(2), current.generation, current.commitment.root, encoded.checksum,
      ByteLimit(ManagedManifestBytes)).value
  let header = encodeManagedJournalHeader(manifest.checksum, limits.journalBytes).value
  let originalCurrent = readFile(path & "/CURRENT")
  let originalSnapshot = readFile(path & "/snapshot-0000000000000001.bin")
  let originalJournal = readFile(path & "/journal-0000000000000001.wal")
  assert file.close == FileError.None
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    if openManagedFileRepository(file, path, default(StorageChainId), limits, schema) !=
        FileError.None: exitCrash(86)
    if shortWrites: limitWrites(8) # Every staged extent remains a genuine kernel write.
    if startCrash() != 0: exitCrash(87)
    let replaced = file.compact(file.snapshot.value, roots)
    if replaced.error != FileError.None or replaced.value.cleanup != FileError.None: exitCrash(88)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 4096
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  if shortWrites:
    assert operation == writeIo and result < 4096
    let stagedNames = ["snapshot-0000000000000002.bin", "journal-0000000000000002.wal", "CURRENT.next"]
    var prior = 0
    for index, bytes in [encoded.bytes, header, manifest.bytes]:
      let chunks = (bytes.len+7) div 8
      let progressed = min(max(int(result)-prior, 0), chunks)
      let extent = min(bytes.len, progressed*8)
      var exact = ""
      for offset in 0..<extent: exact.add(char(bytes[offset]))
      let name = if skip == 4096 and index == 2: "CURRENT" else: stagedNames[index]
      if extent == 0:
        assert not sampleExists(path & "/" & name)
      else:
        assert readFile(path & "/" & name) == exact
      prior += chunks
    if skip == 4096: assert result == uint64(prior)
  let visibleCurrent = readFile(path & "/CURRENT")
  let selectedOld = visibleCurrent == originalCurrent
  if operation == writeIo and skip != 4096: assert selectedOld
  if operation == renameIo or operation == unlinkIo or skip == 4096: assert not selectedOld
  for name in ["snapshot-0000000000000001.bin", "journal-0000000000000001.wal"]:
    if sampleExists(path & "/" & name):
      assert readFile(path & "/" & name) == (if name ==
          "snapshot-0000000000000001.bin": originalSnapshot else: originalJournal)
  let names = ["CURRENT.next", "snapshot-0000000000000002.bin", "journal-0000000000000002.wal"]
  var present: seq[bool] = @[]
  var forensic: seq[string] = @[]
  for name in names:
    let exists = sampleExists(path & "/" & name)
    present.add(exists)
    forensic.add(if exists: readFile(path & "/" & name) else: "")
  assert openManagedFileRepository(file, path, default(StorageChainId), limits, schema) == FileError.None
  assert uint64(file.snapshot.value.generation) == 2
  assert uint64(file.managedUsage.value.epoch) == (if selectedOld: 1'u64 else: 2'u64)
  checkCrashMap(file.snapshot.value, 8)
  assert file.snapshotContext.value == afterContext
  assert readFile(path & "/CURRENT") == visibleCurrent
  for index, name in names:
    assert sampleExists(path & "/" & name) == present[index]
    if present[index]: assert readFile(path & "/" & name) == forensic[index]
  if selectedOld:
    assert file.discardManagedStaging == FileError.None
    let resumed = file.compact(file.snapshot.value, roots).value
    assert resumed.cleanup == FileError.None and uint64(resumed.epoch) == 2
  else:
    assert file.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert file.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert file.cleanupRetiredEpoch(ManagedEpoch(2)) == FileError.InvalidRetention
  assert file.cleanupRetiredEpoch(ManagedEpoch(3)) == FileError.InvalidRetention
  assert file.close == FileError.None
  assert openManagedFileRepository(file, path, default(StorageChainId), limits, schema) == FileError.None
  assert uint64(file.managedUsage.value.epoch) == 2 and uint64(file.snapshot.value.generation) == 2
  checkCrashMap(file.snapshot.value, 8)
  assert file.snapshotContext.value == afterContext
  if retainedContext:
    for value in [7'u8, 8'u8]:
      let expected = storageTrie(value)
      let entries = restoreHistoricalStateEntries(file.snapshot.value, expected.commitment.root,
          limits.repository.codec.trie).value
      assert entries.len == 2 and entries[0].value == @[value] and entries[1].value == @[9'u8]
  else:
    assert restoreHistoricalStateEntries(file.snapshot.value, held.commitment.root,
        limits.repository.codec.trie).error != RepositoryError.None
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  assert heldContext == beforeContext
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
