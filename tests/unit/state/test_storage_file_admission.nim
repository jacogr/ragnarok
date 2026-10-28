# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real special inodes, incompatible identities, bounded files and partial tails refuse unchanged.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded

proc creationMask(value: uint32): uint32 {.importc: "umask", cdecl, header: "<sys/stat.h>".}
  ## The SDK controls/restores actual permission bits; the pinned POSIX module omits this binding.
proc makeFifo(path: cstring, mode: uint32): cint {.importc: "mkfifo", cdecl,
    header: "<sys/stat.h>".}
  ## Create a real named pipe through the standard SDK, without adding production FFI.

proc main() {.raises.} =
  ## Isolate known test paths and restore the process umask before the native executable retires.
  var path = "storage-admission.db"
  var fifo = "storage-admission.fifo"
  var link = "storage-admission.link"
  var missing = "storage-admission-missing.db"
  let mask = creationMask(0o077)
  defer: discard creationMask(mask)
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  let chain = default(StorageChainId)
  var owner = default(FileRepository)
  defer:
    if owner.opened: discard owner.close # Any test IO exception still retires its own live descriptors.
    discard posix.unlink(path.toCString())
    discard posix.unlink(fifo.toCString())
    discard posix.unlink(link.toCString())
  assert initializeFileRepository(owner, path, chain, limits) == FileError.None
  let initial = storageTrie()
  discard owner.publish(owner.snapshot.value, exportFullTrie(initial,
      limits.repository.codec.records).value).value
  assert owner.close == FileError.None
  let original = readFile(path)
  var metadata = default(Stat)
  assert posix.stat(path.toCString(), metadata) == 0
  assert (uint32(metadata.st_mode) and 0o777'u32) == 0o600'u32
  var short = limits
  short.bytes = ByteLimit(original.len-1)
  assert openFileRepository(owner, path, chain, short) == FileError.LimitExceeded
  assert not owner.opened and readFile(path) == original
  writeFile(path, original & "x")
  assert openFileRepository(owner, path, chain, limits) == FileError.InvalidJournal
  assert not owner.opened and readFile(path) == original & "x"
  assert initializeFileRepository(owner, path, chain, limits) == FileError.AlreadyExists
  assert readFile(path) == original & "x" # Explicit creation cannot repair/reset an existing selector history.
  var corrupt = original
  corrupt[0] = 'x'
  writeFile(path, corrupt)
  assert openFileRepository(owner, path, chain, limits) == FileError.WrongIdentity
  assert not owner.opened and readFile(path) == corrupt
  writeFile(path, original)
  assert makeFifo(fifo.toCString(), 0o600) == 0
  assert openFileRepository(owner, fifo, chain, limits) == FileError.IoFailure
  assert not owner.opened
  assert posix.symlink(path.toCString(), link.toCString()) == 0
  assert openFileRepository(owner, link, chain, limits) == FileError.IoFailure
  assert readFile(path) == original
  assert posix.unlink(link.toCString()) == 0
  assert posix.symlink(missing.toCString(), link.toCString()) == 0
  assert openFileRepository(owner, link, chain, limits) == FileError.IoFailure
  assert openFileRepository(owner, ".", chain, limits) == FileError.IoFailure
  assert openFileRepository(owner, "", chain, limits) == FileError.InvalidPath
  assert openFileRepository(owner, "bad\0path", chain, limits) == FileError.InvalidPath
  assert not owner.opened
  assert openFileRepository(owner, path, chain, limits) == FileError.None
  assert uint64(owner.snapshot.value.generation) == 1
  assert owner.close == FileError.None

try:
  main()
except:
  quit(2) # Native fixture IO/setup failures cannot count as expected repository refusal.
echo "PASS storage file admission: modes, bounded reads, partial/corrupt tails and special inodes"
