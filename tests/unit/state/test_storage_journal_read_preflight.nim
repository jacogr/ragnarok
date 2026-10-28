# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An oversized journal refuses before buffering under a one-MiB heap and preserves its valid prefix.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie

proc truncateNative(fd: cint, extent: int64): cint {.importc: "ftruncate", cdecl,
    header: "<unistd.h>".}
  ## The isolated sparse tail needs no large Nim allocation or production recovery operation.

proc main() {.raises.} =
  ## Refusal must release its lock and preserve the authored prefix and independently retained view.
  var path = "storage-journal-read-preflight"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(4*1024*1024))
  var owner = default(FileRepository)
  defer:
    if owner.opened: discard owner.close
  let initial = storageTrie()
  assert initializeFileRepository(owner, path, default(StorageChainId), limits) == FileError.None
  let head = owner.publish(owner.snapshot.value, exportFullTrie(initial,
    limits.repository.codec.records).value).value
  assert owner.close == FileError.None
  let original = readFile(path)
  var fd = posix.open(path.toCString(), O_RDWR)
  assert fd >= 0
  defer:
    if fd >= 0: discard posix.close(fd)
  assert truncateNative(fd, 16*1024*1024) == 0
  echo "journal preflight"
  let refused = openFileRepository(owner, path, default(StorageChainId), limits)
  assert refused == FileError.LimitExceeded and not owner.opened, "known extent must refuse"
  var metadata = default(Stat)
  assert posix.fstat(fd, metadata) == 0 and metadata.st_size == 16*1024*1024,
    "refusal must preserve the sparse extent"
  assert uint64(head.generation) == 1 and head.storedNodes == 3
  # Only this test removes its deliberately authored tail; the production reader must not truncate.
  assert truncateNative(fd, int64(original.len)) == 0
  assert posix.close(fd) == 0
  fd = -1
  assert readFile(path) == original, "refusal must preserve every byte of the valid prefix"
  var exact = limits
  exact.bytes = ByteLimit(original.len)
  assert openFileRepository(owner, path, default(StorageChainId), exact) == FileError.None
  let reopened = owner.snapshot.value
  assert array[32, byte](reopened.commitment.root) == array[32, byte](head.commitment.root) and
      uint64(reopened.generation) == uint64(head.generation)
  assert owner.close == FileError.None and readFile(path) == original
  assert posix.unlink(path.toCString()) == 0

try:
  main()
except:
  quit(2)
echo "PASS journal read preflight: bounded refusal under one-MiB heap, unchanged prefix and strict reopen"
