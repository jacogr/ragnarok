# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real kernel short writes and abrupt child exit check managed append and epoch-publication boundaries.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples]
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest,
    io as managed_io]
import ../../../src/storage/snapshot_codec
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/journal_codec
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
type
  ResourceLimit {.importc: "struct rlimit", header: "<sys/resource.h>", bycopy.} = object
    ## Exact supported 64-bit SDK fields constrain only the forked writer.
    current {.importc: "rlim_cur".}: uint64
    maximum {.importc: "rlim_max".}: uint64
  SignalHandler = proc(value: cint) {.cdecl, raises: [].} ## Nonallocating callback keeps kernel refusal observable.
let fileLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint
let sizeSignal {.importc: "SIGXFSZ", header: "<signal.h>".}: cint
let signalError {.importc: "SIG_ERR", header: "<signal.h>".}: SignalHandler
proc getLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "getrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Inspect the inherited hard ceiling before selecting a smaller soft limit.
proc setLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "setrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Change only the isolated child, never the native runner's resource budget.
proc install(signal: cint, handler: SignalHandler): SignalHandler {.importc: "signal", cdecl,
    header: "<signal.h>".}
  ## Keep SIGXFSZ as a typed write error rather than accepting signal termination as evidence.
proc ignore(value: cint) {.cdecl, raises: [].} =
  ## Signal handling performs no allocation, output or storage operation.
  discard

proc join(child: Pid) =
  ## Every child must report a normal successful exit; signal death is never an accepted fault verdict.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "managed failure child"
proc appendCut(cut: int, number: int) {.raises.} =
  ## The kernel stops the actual append at an exact extent, leaving its selected prefix untouched.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let first = storageTrie(7)
  let second = storageTrie(8)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(first,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  let batch = exportTrieChanges(first, second, limits.repository.codec.records).value
  let frame = encodeContextJournalFrame(RepositoryGeneration(2), batch, [2'u8], limits.contextBytes,
    limits.repository.codec, limits.journalBytes).value
  let extent = if cut < 0: frame.len else: cut
  let path = "storage-managed-fault-append-" & $number
  var repository = default(ManagedRepository)
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [1'u8], limits, StorageSchema.FullStateV1) == FileError.None
  assert repository.close == FileError.None
  let journalPath = path & "/journal-0000000000000001.wal"
  let original = readFile(journalPath)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var writer = default(ManagedRepository)
    if openManagedRepository(writer, path, default(StorageChainId), limits,
        StorageSchema.FullStateV1) != FileError.None: posix.exitnow(3)
    let prior = writer.snapshot.value
    var policy = default(ResourceLimit)
    let ceiling = uint64(original.len+extent)
    if getLimit(fileLimit, addr policy) != 0 or ceiling > policy.maximum: posix.exitnow(4)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(5)
    policy.current = ceiling
    if setLimit(fileLimit, addr policy) != 0: posix.exitnow(6)
    let outcome = writer.publish(prior, batch, [2'u8])
    if extent == frame.len:
      if outcome.error != FileError.None: posix.exitnow(7)
    else:
      if outcome.error != FileError.IoFailure: posix.exitnow(8)
      if writer.snapshot.error != FileError.RecoveryRequired: posix.exitnow(9)
      if writer.usage.error != FileError.RecoveryRequired: posix.exitnow(10)
      if writer.synchronize.error != FileError.RecoveryRequired: posix.exitnow(11)
      if writer.publish(prior, batch, [2'u8]).error != FileError.RecoveryRequired: posix.exitnow(12)
      if restoreStateEntries(prior, prior.commitment.root, limits.repository.codec.trie).error !=
          RepositoryError.None:
        posix.exitnow(13)
    posix.exitnow(0) # Deliberately skip close/destructors; the kernel must retire the stable lock.
  join(child)
  let interrupted = readFile(journalPath)
  assert interrupted.len == original.len+extent
  assert interrupted[0..<original.len] == original
  let opened = openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1)
  if extent == 0 or extent == frame.len:
    assert opened == FileError.None
    assert uint64(repository.snapshot.value.generation) == (if extent == 0: 1'u64 else: 2'u64)
    assert repository.snapshotContext.value == (if extent == 0: @[1'u8] else: @[2'u8])
    assert repository.close == FileError.None
  else:
    assert opened == FileError.InvalidJournal
    assert recoverManagedRepository(repository, path, default(StorageChainId), limits,
      initial.generation, initial.commitment.root, StorageSchema.FullStateV1) == FileError.None
    assert repository.snapshotContext.value == @[1'u8] and readFile(journalPath) == original
    assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1)])
  assert memory.close == RepositoryError.None
proc epochCut(cut: int) {.raises.} =
  ## Exit after each durable staging boundary; only CURRENT replacement changes restart selection.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(storageTrie(),
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  let path = "storage-managed-fault-epoch-" & $cut
  var repository = default(ManagedRepository)
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [1'u8], limits, StorageSchema.FullStateV1) == FileError.None
  assert repository.close == FileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var directory = default(ManagedDirectory)
    if openManagedDirectory(directory, path) != FileError.None: posix.exitnow(3)
    let current = readManagedFile(directory, ManagedFileKind.Current, ManagedEpoch(0), ByteLimit(
        ManagedManifestBytes)).value
    let manifest = decodeManagedManifest(current, default(StorageChainId),
        StorageSchema.FullStateV1,
      ByteLimit(ManagedManifestBytes)).value
    let snapshot = readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1),
        limits.snapshotBytes).value
    if createManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(2), snapshot,
        limits.snapshotBytes) != FileError.None: posix.exitnow(4)
    if cut == 1: posix.exitnow(0)
    let next = encodeManagedManifest(default(StorageChainId), StorageSchema.FullStateV1,
      ManagedEpoch(2), manifest.generation, manifest.root, manifest.snapshotChecksum,
      ByteLimit(ManagedManifestBytes)).value
    let header = encodeManagedJournalHeader(next.checksum, limits.journalBytes).value
    if createManagedFile(directory, ManagedFileKind.Journal, ManagedEpoch(2), header,
        limits.journalBytes) != FileError.None: posix.exitnow(5)
    if cut == 2: posix.exitnow(0)
    if cut == 3:
      writeFile(path & "/CURRENT.next", "partial")
      posix.exitnow(0) # A visible partial pending manifest never grants authority.
    if replaceManagedManifest(directory, next.bytes, ByteLimit(ManagedManifestBytes)) !=
        FileError.None:
      posix.exitnow(6)
    posix.exitnow(0) # Old files intentionally survive publication; cleanup cannot affect head selection.
  join(child)
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  assert uint64(repository.physicalEpoch.value) == (if cut < 4: 1'u64 else: 2'u64)
  assert uint64(repository.snapshot.value.generation) == 1 and repository.snapshotContext.value == @[1'u8]
  if cut < 4:
    assert repository.discardManagedStaging == FileError.None
  else:
    assert repository.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
  assert memory.close == RepositoryError.None
proc compactCut() {.raises.} =
  ## A real partial staged snapshot cannot change CURRENT or permit reuse of an uncertain live owner.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(storageTrie(),
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  let path = "storage-managed-fault-compaction"
  var repository = default(ManagedRepository)
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [1'u8], limits, StorageSchema.FullStateV1) == FileError.None
  assert repository.close == FileError.None
  let original = readFile(path & "/CURRENT")
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var writer = default(ManagedRepository)
    if openManagedRepository(writer, path, default(StorageChainId), limits,
        StorageSchema.FullStateV1) != FileError.None: posix.exitnow(3)
    var policy = default(ResourceLimit)
    if getLimit(fileLimit, addr policy) != 0: posix.exitnow(4)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(5)
    policy.current = 16
    if setLimit(fileLimit, addr policy) != 0: posix.exitnow(6)
    let prior = writer.snapshot.value
    if writer.compact(prior, [prior.commitment.root]).error != FileError.IoFailure: posix.exitnow(7)
    if writer.snapshot.error != FileError.RecoveryRequired: posix.exitnow(8)
    if writer.discardManagedStaging != FileError.RecoveryRequired: posix.exitnow(9)
    posix.exitnow(0)
  join(child)
  assert readFile(path & "/CURRENT") == original
  assert readFile(path & "/snapshot-0000000000000002.bin").len == 16
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  assert uint64(repository.physicalEpoch.value) == 1
  assert repository.discardManagedStaging == FileError.None
  let prior = repository.snapshot.value
  assert repository.compact(prior, [prior.commitment.root]).error == FileError.None
  assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
  assert memory.close == RepositoryError.None
proc main() {.raises.} =
  ## Cover prefix/header/body/checksum tears and all selected epoch staging barriers.
  for index, cut in [0, 1, 7, 8, 16, 32, 100, -1]: appendCut(cut, index)
  for cut in 1..4: epochCut(cut)
  compactCut()
try:
  main()
except:
  quit(2)
echo "PASS storage managed failures: kernel short writes, poisoned owners, exact repair and abrupt epoch-stage restart"
