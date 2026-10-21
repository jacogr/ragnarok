# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real kernel zero/partial writes require explicit exact-prefix recovery before append can resume.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/storage_samples
import ../../../src/storage/[file_repository, node_repository, node_records, full_state_trie,
    database_identity, journal_codec]
import ../../../src/codec/[bounded, state_trie]

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

proc contextInitialize(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits): FileError =
  ## Select the contextual physical schema explicitly; node-only opens must refuse it.
  initializeFileRepository(repository, path, chain, limits, StorageSchema.FullStateV1)
proc contextOpen(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits): FileError =
  ## Strict contextual reopen never guesses another frame format.
  openFileRepository(repository, path, chain, limits, StorageSchema.FullStateV1)
proc contextRecover(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, generation: RepositoryGeneration, root: StateRoot): FileError =
  ## Recovery retains exactly the independently selected prefix and its context.
  recoverFileRepository(repository, path, chain, limits, generation, root,
      StorageSchema.FullStateV1)
proc contextPublish(repository: var FileRepository, expected: RepositoryView,
    batch: TrieExport): FileResult[RepositoryView] =
  ## One authored byte identifies which generation supplied the selected application context.
  repository.publish(expected, batch, [byte(uint64(expected.generation)+1)])

proc attempt(extra: uint64, succeeds: bool) {.raises.} =
  ## No live lock owner crosses fork; parent and child verify each selected revision independently.
  var path = "storage-recovery.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576),
      contextBytes: ByteLimit(16))
  let chain = default(StorageChainId)
  let initial = storageTrie()
  let target = initial.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put, value: @[8'u8])]).value
  let batch = exportTrieChanges(initial, target, limits.repository.codec.records).value
  let frame = encodeContextJournalFrame(RepositoryGeneration(2), batch, [2'u8], limits.contextBytes,
      limits.repository.codec, limits.bytes).value
  var setup = default(FileRepository)
  defer:
    if setup.opened: discard setup.close # Fixture exceptions cannot leak an initialized owner.
  assert contextInitialize(setup, path, chain, limits) == FileError.None
  discard setup.contextPublish(setup.snapshot.value, exportFullTrie(initial,
      limits.repository.codec.records).value).value
  assert setup.close == FileError.None
  defer: discard posix.unlink(path.toCString())
  let original = readFile(path)
  assert extra <= uint64(frame.len)+1 and uint64(original.len) <= high(uint64)-extra
  let ceiling = uint64(original.len)+extra
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var policy = default(ResourceLimit)
    if getLimit(fileLimit, addr policy) != 0 or ceiling > policy.maximum: posix.exitnow(3)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(4)
    policy.current = ceiling
    if setLimit(fileLimit, addr policy) != 0: posix.exitnow(5)
    var file = default(FileRepository)
    if contextOpen(file, path, chain, limits) != FileError.None: posix.exitnow(6)
    let prior = file.snapshot.value
    assert file.snapshotContext.value == @[1'u8]
    let outcome = file.contextPublish(prior, batch)
    let wanted = if succeeds: FileError.None else: FileError.IoFailure
    if outcome.error != wanted: posix.exitnow(7)
    if succeeds:
      if uint64(outcome.value.generation) != 2: posix.exitnow(8)
    else:
      if file.snapshotContext.error != FileError.RecoveryRequired: posix.exitnow(16)
      if file.snapshot.error != FileError.RecoveryRequired: posix.exitnow(9)
      if file.synchronize.error != FileError.RecoveryRequired: posix.exitnow(15)
      if file.contextPublish(prior, batch).error != FileError.RecoveryRequired: posix.exitnow(10)
      if uint64(prior.generation) != 1: posix.exitnow(11)
      let held = restoreFullTrie(prior, initial.commitment.root,
        FullStateTrieLimits(trie: limits.repository.codec.trie))
      if held.error != RepositoryError.None or held.value.lookup(storageKey(0)).value.bytes != @[7'u8]:
        posix.exitnow(13) # Child-side old views remain independent of the incomplete physical append.
    if file.close != FileError.None: posix.exitnow(12)
    posix.exitnow(0) # Avoid destruction of inherited ARC graphs; no cross-process ARC occupancy claim is made.
  var joined = false
  defer:
    if not joined:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0)
  var childStatus = 0.cint
  assert posix.waitpid(child, childStatus, 0) == child
  joined = true
  assert WIFEXITED(childStatus) and WEXITSTATUS(childStatus) == 0, "real journal write-limit child"
  let interrupted = readFile(path)
  assert interrupted[0..<original.len] == original # Appends never replace a byte of the selected prefix.
  var file = default(FileRepository)
  defer:
    if file.opened: discard file.close # Every parent IO/setup error still retires this exact owner.
  if not succeeds and extra > 0:
    assert contextOpen(file, path, chain, limits) == FileError.InvalidJournal
    assert not file.opened
    assert interrupted.len == original.len+int(extra)
  else:
    assert contextOpen(file, path, chain, limits) == FileError.None
    assert uint64(file.snapshot.value.generation) == (if succeeds: 2'u64 else: 1'u64)
    assert file.close == FileError.None
  if not succeeds:
    assert contextRecover(file, path, chain, limits, RepositoryGeneration(2),
      initial.commitment.root) == FileError.RecoveryMismatch
    assert readFile(path) == interrupted and not file.opened
    var wrongRoot = array[32, byte](initial.commitment.root)
    wrongRoot[0] = wrongRoot[0] xor 1
    assert contextRecover(file, path, chain, limits, RepositoryGeneration(1),
      StateRoot(wrongRoot)) == FileError.RecoveryMismatch
    assert readFile(path) == interrupted and not file.opened
    assert contextRecover(file, path, chain, limits, RepositoryGeneration(1),
      initial.commitment.root) == FileError.None
    assert readFile(path) == original
    let prior = file.snapshot.value
    assert file.snapshotContext.value == @[1'u8]
    assert contextRecover(file, path, chain, limits, RepositoryGeneration(1),
      initial.commitment.root) == FileError.Busy # Recovery cannot redirect an already active owner.
    assert restoreFullTrie(prior, initial.commitment.root,
      FullStateTrieLimits(trie: limits.repository.codec.trie)).value.lookup(storageKey(
          0)).value.bytes == @[7'u8]
    let next = file.contextPublish(prior, batch).value
    assert uint64(next.generation) == 2 # Append resumes at truncated EOF, not the descriptor's previous read offset.
    assert file.close == FileError.None
  assert contextOpen(file, path, chain, limits) == FileError.None
  assert restoreFullTrie(file.snapshot.value, target.commitment.root,
    FullStateTrieLimits(trie: limits.repository.codec.trie)).value.lookup(storageKey(
        0)).value.bytes == @[8'u8]
  assert file.snapshotContext.value == @[2'u8]
  assert file.close == FileError.None
  assert openFileRepository(file, path, chain, limits) == FileError.WrongIdentity
  assert not file.opened
  let complete = readFile(path)
  assert contextRecover(file, path, chain, limits, RepositoryGeneration(1),
    initial.commitment.root) == FileError.RecoveryMismatch # Never discard a complete visible successor to satisfy an old token.
  assert readFile(path) == complete
  var corrupted = complete
  corrupted[corrupted.high] = char(byte(corrupted[corrupted.high]) xor 1)
  writeFile(path, corrupted)
  assert contextRecover(file, path, chain, limits, RepositoryGeneration(1),
    initial.commitment.root) == FileError.InvalidJournal
  assert not file.opened and readFile(path) == corrupted # Complete checksum corruption requires investigation, not prefix truncation.
  for octet in [char(0), char(255)]:
    var impossible = original
    for i in 0..<8: impossible.add(octet) # Zero/maximum declared lengths cannot be plausible interrupted frames.
    writeFile(path, impossible)
    assert contextRecover(file, path, chain, limits, RepositoryGeneration(1),
      initial.commitment.root) == FileError.InvalidJournal
    assert not file.opened and readFile(path) == impossible

proc contextBoundaries() {.raises.} =
  ## Context limits precede publication, and both input/output buffers stay detached from private metadata.
  var path = "storage-context-bounds.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576),
      contextBytes: ByteLimit(2))
  var file = default(FileRepository)
  assert contextInitialize(file, path, default(StorageChainId), limits) == FileError.None
  defer:
    if file.opened: discard file.close # Every checked refusal must still retire this explicit owner.
    discard posix.unlink(path.toCString())
  let batch = exportFullTrie(storageTrie(), limits.repository.codec.records).value
  let initial = file.snapshot.value
  assert file.publish(initial, batch, [1'u8, 2, 3]).error == FileError.LimitExceeded
  assert uint64(file.snapshot.value.generation) == 0 and file.snapshotContext.value.len == 0
  var source = @[1'u8, 2]
  discard file.publish(initial, batch, source).value
  source[0] = 99
  var copied = file.snapshotContext.value
  copied[0] = 98
  assert file.snapshotContext.value == @[1'u8, 2]
  assert file.close == FileError.None and copied == @[98'u8, 2]
  assert file.snapshotContext.error == FileError.Uninitialized
  let complete = readFile(path)
  var impossible = complete
  for index in 0..<8:
    impossible.add(char(if index == 0: 108 else: 0)) # Too short for context length plus fixed record header.
  writeFile(path, impossible)
  let root = storageTrie().commitment.root
  assert contextRecover(file, path, default(StorageChainId), limits,
    RepositoryGeneration(1), root) == FileError.InvalidJournal
  assert not file.opened and readFile(path) == impossible


proc main() {.raises.} =
  ## Exact and ample kernel ceilings prove the same publisher succeeds without a refusal.
  contextBoundaries()
  let initial = storageTrie()
  let target = initial.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put, value: @[8'u8])]).value
  let limits = storageLimits()
  let batch = exportTrieChanges(initial, target, limits.codec.records).value
  let size = uint64(encodeContextJournalFrame(RepositoryGeneration(2), batch, [2'u8], ByteLimit(16),
      limits.codec, ByteLimit(1048576)).value.len)
  for extra in [0'u64, 1'u64, size div 2, size-1]: attempt(extra, false)
  for extra in [size, size+1]: attempt(extra, true)
try:
  main()
except:
  quit(2) # Setup/fixture IO failures cannot substitute for expected kernel refusal/recovery.
echo "PASS storage context repository: atomic context and nodes, kernel short writes, schema and trusted recovery"
