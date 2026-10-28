# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refuse every required hash stage independently before a durable StateStore update can publish.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Restore primitive behavior between independent journal fixtures.
proc failAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse the next required invocation after a permitted prefix of hash calls.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Require every failure to be the selected operation, not unrelated fixture setup.
proc run() {.raises.} =
  ## Exhaust the update's actual hash stages; successful controls use the same owner and inputs.
  var failures = 0
  var successes = 0
  for allowed in 0..<16:
    reset(0)
    var path = "disk-store-hash-failure.db"
    let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
    let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(1),
      writeValueBytes: ByteLimit(64))
    let memory = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8]),
      StateEntry(key: storageKey(128), value: @[9'u8])], policy).value
    var disk = default(DiskStateStore)
    defer:
      if disk.opened: discard disk.close # Any assertion/setup failure still retires this native owner.
    let initial = initializeDiskStateStore(disk, path, default(StorageChainId),
        memory.snapshot.value, limits).value
    defer: discard posix.unlink(path.toCString())
    let before = readFile(path)
    failAfter(cint(allowed))
    let changed = disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8])])
    if changed.error == DiskStoreError.None:
      inc successes
      assert calls() <= cint(allowed) and uint64(disk.generation.value) == 2
      assert changed.value.lookup(storageKey(0)).value.bytes == @[8'u8]
    else:
      inc failures
      assert calls() == cint(allowed+1)
      assert changed.error in {DiskStoreError.StateFailure, DiskStoreError.FileFailure}
      if changed.error == DiskStoreError.StateFailure:
        assert changed.stateError == StateStoreError.BackendFailure
      else:
        assert changed.fileError in {FileError.InvalidBatch, FileError.InvalidFrame}
      assert sameStateSnapshot(initial, disk.snapshot.value)
      assert uint64(disk.generation.value) == 1 and readFile(path) == before
    assert initial.lookup(storageKey(0)).value.bytes == @[7'u8]
    reset(0)
    assert disk.close == FileError.None
  assert failures > 2 and successes > 0 # Both staged refusals and real successful controls must execute.
try:
  run()
except:
  quit(2) # Setup IO failures cannot satisfy a cryptographic refusal case.
echo "PASS disk store hash failures: every required stage preserves prior bytes and snapshot identity"
