# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit staging cleanup remains bounded after actual unlink or directory-sync refusal.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples, storage_io, storage_bootstrap_faults]
import ../../../src/storage/[full_state_trie, node_repository, node_records, file_repository,
  managed_repository, managed_manifest, database_identity]
import ../../../src/codec/bounded
proc scenario(syncFault: bool, skip, failures: cint): uint64 {.raises.} =
  ## Build real unselected successor files, preserve a farther epoch, then refuse exact cleanup boundaries.
  resetIo()
  let path = "storage-staging-io-" & $syncFault & "-" & $skip & "-" & $failures & "-" & $int(
      storageProcessId())
  let limits = managedStorageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # Fixture retirement cannot inherit the intentional syscall refusal.
    if file.opened: discard file.close
  assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
      limits) == FileError.None
  let next = file.publish(file.snapshot.value, exportTrieChanges(a, b,
      limits.repository.codec.records).value).value
  resetIo()
  armIo(renameIo, 0, 1, failedIo)
  assert file.compact(next, [next.commitment.root]).error == FileError.IoFailure
  assert pendingIo() == 0
  resetIo()
  assert file.close == FileError.None
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  let current = readFile(path & "/CURRENT")
  let selectedSnapshot = readFile(path & "/snapshot-0000000000000001.bin")
  let selectedJournal = readFile(path & "/journal-0000000000000001.wal")
  writeFile(path & "/snapshot-0000000000000003.bin", "farther snapshot")
  writeFile(path & "/journal-0000000000000003.wal", "farther journal")
  resetIo()
  let operation = if syncFault: syncIo else: unlinkIo
  armIo(operation, skip, failures, failedIo)
  let cleaned = file.discardManagedStaging
  result = ioCalls(operation)
  assert pendingIo() == 0
  resetIo()
  assert cleaned == (if failures == 0: FileError.None else: FileError.IoFailure)
  assert file.snapshot.error == FileError.None and uint64(file.managedUsage.value.epoch) == 1
  assert readFile(path & "/CURRENT") == current
  assert readFile(path & "/snapshot-0000000000000001.bin") == selectedSnapshot
  assert readFile(path & "/journal-0000000000000001.wal") == selectedJournal
  var present: seq[bool] = @[]
  var retained: seq[string] = @[]
  let names = ["CURRENT.next", "snapshot-0000000000000002.bin", "journal-0000000000000002.wal"]
  for name in names:
    let exists = sampleExists(path & "/" & name)
    present.add(exists)
    retained.add(if exists: readFile(path & "/" & name) else: "")
  assert file.close == FileError.None
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  for index, name in names:
    assert sampleExists(path & "/" & name) == present[index]
    if present[index]: assert readFile(path & "/" & name) == retained[index]
  assert file.discardManagedStaging == FileError.None
  assert file.discardManagedStaging == FileError.None
  assert readFile(path & "/snapshot-0000000000000003.bin") == "farther snapshot"
  assert readFile(path & "/journal-0000000000000003.wal") == "farther journal"
  assert readFile(path & "/CURRENT") == current
  let entries = restoreStateEntries(file.snapshot.value, next.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[8'u8] and entries[1].value == @[9'u8]
  assert file.close == FileError.None and source.close == RepositoryError.None
  for name in ["snapshot-0000000000000003.bin", "journal-0000000000000003.wal"]:
    var child = path & "/" & name
    assert posix.unlink(child.toCString()) == 0
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
proc main() {.raises.} =
  ## Three explicit names each have one unlink and one namespace barrier; no directory scan is permitted.
  for syncFault in [false, true]:
    let count = scenario(syncFault, 0, 0)
    assert count == 3
    for skip in 0..<int(count):
      assert scenario(syncFault, cint(skip), 1) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage staging cleanup IO: bounded refusals, unchanged selection, strict restart and farther-epoch preservation"
