# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real kernel-limited durable StateStore updates preserve retained views and require explicit recovery.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/storage_samples
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/[database_identity, journal_codec]
import ../../../src/codec/bounded
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
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

proc attempt(extra: uint64, succeeds: bool) {.raises.} =
  ## Children own their locks independently; actual write refusals must return typed errors before exit.
  var path = "disk-store-recovery.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  let chain = default(StorageChainId)
  let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(4),
    writeValueBytes: ByteLimit(64))
  var initialStore = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8]),
    StateEntry(key: storageKey(128), value: @[9'u8])], policy).value
  let initial = initialStore.snapshot.value
  let writes = [StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8])]
  let target = initialStore.apply(writes).value
  let batch = exportStateChanges(initial, target, limits.repository.codec.records).value
  let frame = encodeJournalFrame(RepositoryGeneration(2), batch, limits.repository.codec,
      limits.bytes).value
  var setup = default(DiskStateStore)
  defer:
    if setup.opened: discard setup.close # Fixture exceptions cannot leak a lock owner.
  assert initializeDiskStateStore(setup, path, chain, initial, limits).error == DiskStoreError.None
  assert setup.close == FileError.None
  defer: discard posix.unlink(path.toCString())
  let original = readFile(path)
  assert extra <= uint64(frame.len)+1 and uint64(original.len) <= high(uint64)-extra
  let ceiling = uint64(original.len)+extra
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var policyLimit = default(ResourceLimit)
    if getLimit(fileLimit, addr policyLimit) != 0 or ceiling > policyLimit.maximum: posix.exitnow(3)
    if install(sizeSignal, ignore) == signalError: posix.exitnow(4)
    policyLimit.current = ceiling
    if setLimit(fileLimit, addr policyLimit) != 0: posix.exitnow(5)
    var disk = default(DiskStateStore)
    let opened = openDiskStateStore(disk, path, chain, initial.commitment.root,
      RepositoryGeneration(1), policy, limits)
    if opened.error != DiskStoreError.None: posix.exitnow(6)
    let held = opened.value.lookup(storageKey(0)).value
    let outcome = disk.apply(writes)
    if succeeds:
      if outcome.error != DiskStoreError.None or uint64(disk.generation.value) != 2: posix.exitnow(7)
    else:
      if outcome.error != DiskStoreError.FileFailure or outcome.fileError !=
          FileError.IoFailure: posix.exitnow(8)
      if disk.snapshot.fileError != FileError.RecoveryRequired: posix.exitnow(9)
      if disk.apply(writes).fileError != FileError.RecoveryRequired: posix.exitnow(10)
      if disk.synchronize.error != FileError.RecoveryRequired: posix.exitnow(11)
      if not sameStateSnapshot(opened.value, opened.value.forkStateStore.value.snapshot.value): posix.exitnow(12)
    if held.bytes != @[7'u8]: posix.exitnow(13)
    if disk.close != FileError.None: posix.exitnow(14)
    if held.bytes != @[7'u8]: posix.exitnow(15)
    posix.exitnow(0) # No inherited ARC memory is reclaimed or counted across processes.
  var joined = false
  defer:
    if not joined:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0)
  var statusCode = 0.cint
  assert posix.waitpid(child, statusCode, 0) == child
  joined = true
  assert WIFEXITED(statusCode) and WEXITSTATUS(statusCode) == 0
  let interrupted = readFile(path)
  assert interrupted[0..<original.len] == original
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every parent-side fixture refusal releases native resources.
  if not succeeds:
    if extra > 0:
      assert openDiskStateStore(disk, path, chain, initial.commitment.root,
        RepositoryGeneration(1), policy, limits).fileError == FileError.InvalidJournal
      assert not disk.opened and readFile(path) == interrupted
    assert recoverDiskStateStore(disk, path, chain, initial.commitment.root,
      RepositoryGeneration(2), policy, limits).fileError == FileError.RecoveryMismatch
    assert not disk.opened and readFile(path) == interrupted
    let recovered = recoverDiskStateStore(disk, path, chain, initial.commitment.root,
      RepositoryGeneration(1), policy, limits).value
    assert readFile(path) == original and recovered.lookup(storageKey(0)).value.bytes == @[7'u8]
    assert disk.apply(writes).error == DiskStoreError.None and uint64(disk.generation.value) == 2
    assert disk.close == FileError.None
  let restored = openDiskStateStore(disk, path, chain, target.commitment.root,
    RepositoryGeneration(2), policy, limits).value
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert disk.close == FileError.None
  let complete = readFile(path)
  assert recoverDiskStateStore(disk, path, chain, initial.commitment.root,
    RepositoryGeneration(1), policy, limits).fileError == FileError.RecoveryMismatch
  assert not disk.opened and readFile(path) == complete
  var corrupt = complete
  corrupt[corrupt.high] = char(byte(corrupt[corrupt.high]) xor 1)
  writeFile(path, corrupt)
  assert recoverDiskStateStore(disk, path, chain, initial.commitment.root,
    RepositoryGeneration(1), policy, limits).fileError == FileError.InvalidJournal
  assert not disk.opened and readFile(path) == corrupt
proc main() {.raises.} =
  ## Zero/partial writes exercise refusals; exact/ample limits exercise genuine successful controls.
  let initial = storageTrie()
  let target = initial.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put, value: @[8'u8])]).value
  let limits = storageLimits()
  let batch = exportTrieChanges(initial, target, limits.codec.records).value
  let size = uint64(encodeJournalFrame(RepositoryGeneration(2), batch, limits.codec, ByteLimit(
      1048576)).value.len)
  for extra in [0'u64, 1'u64, size div 2, size-1]: attempt(extra, false)
  for extra in [size, size+1]: attempt(extra, true)
try:
  main()
except:
  quit(2) # Fixture IO/setup failures cannot stand in for checked publication failure.
echo "PASS disk store recovery: kernel partial writes, retained readers, strict open and trusted repair"
