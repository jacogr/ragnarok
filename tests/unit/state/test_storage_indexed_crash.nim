# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Large indexed repositories preserve exact full/torn append restart and independent recovery authority.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_growth_samples, managed_storage_samples, storage_io, storage_crash]
import ../../../src/storage/[node_repository, full_state_trie, file_repository, managed_repository,
  managed_manifest, database_identity, journal_codec]
import ../../../src/codec/bounded

proc scenario(managed, torn: bool) {.raises.} =
  ## Fork without a parent file lease, then kill only after an actual complete or eight-byte SDK write.
  resetIo()
  var path = "indexed-crash-" & $managed & "-" & $torn & "-" & $int(storageProcessId())
  let limits = growthLimits()
  let policy = ManagedLimits(repository: limits, roots: ElementLimit(9), snapshotBytes: ByteLimit(
      33554432),
    journalBytes: ByteLimit(33554432), contextBytes: ByteLimit(64))
  let journal = JournalLimits(repository: limits, bytes: policy.journalBytes)
  let fixture = prepareGrowth(8192, 64)
  var source = newNodeRepository(limits)
  let seed = source.publish(source.snapshot.value, fixture.seed).value
  let selected = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    abortCrash() # Even failed assertions retire only the owned child and exact file owner.
    resetIo()
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selected, [],
        policy) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, fixture.seed).value
  let held = file.snapshot.value
  checkGrowthHead(held, fixture.roots[0], 8192, 0)
  assert file.close == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let prefix = readFile(journalPath)
  let encoded = encodeJournalFrame(RepositoryGeneration(2), fixture.changes[0], limits.codec,
      journal.bytes).value
  var complete = prefix
  for octet in encoded:
    complete.add(char(octet)) # Exact expected visible bytes are prepared before supervising the writer.
  let child = forkCrash(writeIo, 0)
  assert child >= 0
  if child == 0:
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), policy)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    if opened != FileError.None: exitCrash(81)
    if torn: limitWrites(8)
    if startCrash() != 0: exitCrash(82)
    if file.publish(file.snapshot.value, fixture.changes[0]).error != FileError.None: exitCrash(83)
    exitCrash(0)
  assert finishCrash() == crashKilled and crashCount() == 1
  let visible = readFile(journalPath)
  if torn:
    var exact = prefix
    for index in 0..<8:
      exact.add(char(encoded[index])) # The witness stops after genuine kernel progress, before completion.
    assert visible == exact
  else:
    assert visible == complete
  let opened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), policy)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  if torn:
    assert opened == FileError.InvalidJournal and not file.opened
    assert readFile(journalPath) == visible
    let wrong = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), policy,
          RepositoryGeneration(0), fixture.roots[0])
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal, RepositoryGeneration(0),
          fixture.roots[0])
    assert wrong == FileError.RecoveryMismatch and not file.opened
    assert readFile(journalPath) == visible
    let repaired = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), policy,
          RepositoryGeneration(1), fixture.roots[0])
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal, RepositoryGeneration(1),
          fixture.roots[0])
    assert repaired == FileError.None and readFile(journalPath) == prefix
    checkGrowthHead(file.snapshot.value, fixture.roots[0], 8192, 0)
    discard file.publish(file.snapshot.value, fixture.changes[0]).value
  else:
    assert opened == FileError.None
  checkGrowthHead(file.snapshot.value, fixture.roots[1], 8192, 1)
  assert readFile(journalPath) == complete
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkGrowthHead(held, fixture.roots[0], 8192, 0)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
proc main() {.raises.} =
  ## Both physical layouts exercise indexed image/replay admission with complete and torn publications.
  for managed in [false, true]:
    for torn in [false, true]:
      scenario(managed, torn)
try:
  main()
except:
  quit(2)
echo "PASS indexed process crash: full addresses, exact prefixes, strict restart and independent repair"
