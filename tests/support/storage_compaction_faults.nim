# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed epoch replacement fixtures expose bounded syscall boundaries and retained map witnesses.
import std/[assertions, syncio]
import ./[storage_samples, managed_storage_samples, storage_io]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/file/repository as file_repository
import ../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../src/storage/database_identity
import ../../src/codec/bounded
proc compactionCase*(label: string, skip, failures: cint, permanent = false,
    writeFault = false): uint64 {.raises.} =
  ## Prepare an obsolete seed, then compact only the selected complete successor under a real directory lease.
  resetIo()
  let path = label & "-" & $skip
  let limits = managedStorageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits.repository)
  let initial = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # No injection may survive test-owned native retirement.
    if file.opened: discard file.close
  assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
      limits) == FileError.None
  let held = file.snapshot.value
  let next = file.publish(held, exportTrieChanges(a, b,
      limits.repository.codec.records).value).value
  let current = readFile(path & "/CURRENT")
  resetIo()
  let operation = if writeFault: writeIo else: syncIo
  armIo(operation, skip, failures, if permanent: failedIo else: interruptedIo)
  let outcome = file.compact(next, [next.commitment.root])
  result = ioCalls(operation)
  assert pendingIo() == 0, "compaction fault boundary did not execute"
  resetIo()
  if permanent:
    # Refused replacement poisons fresh reads; confirmed selection reports retirement refusal separately.
    assert outcome.error in [FileError.None, FileError.IoFailure, FileError.PublishedUnsynced]
    if outcome.error == FileError.None:
      assert outcome.value.cleanup == FileError.IoFailure
      assert uint64(file.managedUsage.value.epoch) == 2
    else:
      assert file.snapshot.error == FileError.RecoveryRequired
  else:
    # Only a genuinely confirmed replacement may return a successful epoch and reclamation receipt.
    let replaced = outcome.value
    assert replaced.cleanup == FileError.None and uint64(replaced.epoch) == 2
    assert replaced.reclaimedNodes > 0 and uint64(replaced.generation) == 2
    let after = file.managedUsage.value
    assert uint64(after.epoch) == 2 and after.journalBytes == uint64(ManagedJournalHeaderBytes)
  assert file.close == FileError.None
  if writeFault and permanent:
    assert readFile(path & "/CURRENT") == current # Staged bytes cannot select a manifest before its complete write.
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  assert uint64(file.snapshot.value.generation) == 2
  let entries = restoreStateEntries(file.snapshot.value, next.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[8'u8] and entries[1].value == @[9'u8]
  assert file.close == FileError.None and source.close == RepositoryError.None
  let old = restoreStateEntries(held, held.commitment.root, limits.repository.codec.trie).value
  assert old.len == 2 and old[0].value == @[7'u8] and old[1].value == @[9'u8]
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
