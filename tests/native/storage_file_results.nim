# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Disk payloads, selected diagnostic alternatives and explicit close have strict native guards.
import std/assertions
import std/cmdline
import std/syncio
import std/posix/posix
import ../support/storage_samples
import ../../src/storage/file_repository as storage_file_repository
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/full_state_trie as storage_full_state_trie
import ../../src/storage/database_identity as storage_database_identity
import ../../src/codec/bounded as codec_bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset primitive refusal before constructing real active owner controls.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Permit private candidate validation, then refuse frame encoding before any append.
proc main() =
  ## Known fixture paths stay under ignored build; only dead prior test processes leave these files.
  fail(0)
  let member = paramStr(1)
  let origin = paramStr(2)
  # The standard runner creates build/tests; it does not create per-family fixture directories.
  var path = "build/tests/storage-file-guard.db"
  discard posix.unlink(path.toCString())
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  var file = default(FileRepository)
  assert initializeFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  if member == "retire":
    if origin == "valid":
      assert file.close == FileError.None
      discard posix.unlink(path.toCString())
    return # A live owner must reject implicit destruction; the next valid control cleans the dead fixture.
  let active = file.snapshot
  let empty = default(FileResult[RepositoryView])
  var selected = empty
  if member == "batch" and origin == "valid":
    selected = file.publish(default(RepositoryView),
      exportFullTrie(storageTrie(), limits.repository.codec.records).value)
  elif member == "frame" and origin == "valid":
    let batch = exportFullTrie(storageTrie(), limits.repository.codec.records).value
    failAfter(3)
    selected = file.publish(active.value, batch) # Three graph-node hashes succeed before the first frame-node hash refuses.
    fail(0)
  assert file.close == FileError.None
  discard posix.unlink(path.toCString())
  if member == "result":
    if origin == "failed": selected = file.snapshot
    elif origin == "valid": selected = active
    echo selected.value.storedNodes
  elif member == "batch": echo ord(selected.batchFailure.error)
  else: echo ord(selected.frameError)
main()
