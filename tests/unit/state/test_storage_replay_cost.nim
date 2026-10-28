# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real closed/reopened journals of both schemas/layouts must hash each physical record exactly once.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the observer while preserving actual primitive output.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count all frame/record/identity checks performed by real-file strict open.
proc payload(value: byte, size: int): seq[byte] =
  ## Authored repeated values cover both inline and hashed JAM leaf encodings.
  result = newSeq[byte](size)
  for index in 0..<size:
    result[index] = value # Distinct successor values force one changed leaf and branch each time.
proc check(view: RepositoryView, root: StateRoot, size: int) =
  ## Compare all actual complete values and metadata after disk replay and explicit owner retirement.
  let entries = restoreStateEntries(view, root, storageLimits().codec.trie).value
  assert uint64(view.generation) == 17 and entries.len == 2
  assert array[31, byte](entries[0].key) == array[31, byte](storageKey(0))
  assert entries[0].value == payload(16, size)
  assert array[31, byte](entries[1].key) == array[31, byte](storageKey(128))
  assert entries[1].value.len == 0
proc scenario(managed: bool, schema: StorageSchema, size, sample: int) {.raises.} =
  ## Strict reopen includes real identity/snapshot/frame checks but no record is hashed again by admission.
  let path = "storage-replay-cost-" & $managed & "-" & $ord(schema) & "-" & $size & "-" & $sample
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
    contextBytes: limits.contextBytes)
  let policy = FullStateTrieLimits(trie: limits.repository.codec.trie, writes: ElementLimit(1),
    writeValueBytes: ByteLimit(64))
  var trie = newFullStateTrie([StateEntry(key: storageKey(0), value: payload(0, size)),
    StateEntry(key: storageKey(128))], policy).value
  let full = exportFullTrie(trie, limits.repository.codec.records).value
  var seed = newNodeRepository(limits.repository)
  let initial = seed.publish(seed.snapshot.value, full).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    if file.opened: discard file.close # Failed assertions must not conceal native lease ownership.
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
      limits, schema) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal, schema) == FileError.None
    discard file.publish(file.snapshot.value, full).value
  for index in 1..16:
    # Prepared sparse revisions are identical for both physical layouts and schemas.
    let next = trie.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put,
      value: payload(byte(index), size))]).value
    let batch = exportTrieChanges(trie, next, limits.repository.codec.records).value
    let context = if schema == StorageSchema.FullStateV1: @[byte(index)] else: @[]
    discard file.publish(file.snapshot.value, batch, context).value
    trie = next
  let root = file.snapshot.value.commitment.root
  let held = file.snapshot.value
  assert file.close == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let before = readFile(journalPath)
  reset(0)
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits, schema) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal, schema) == FileError.None
  # 35 physical record hashes,17 frame/identity-or-snapshot checks and one identity/manifest check.
  let expected = 53+(if size > 32: 17 else: 0)
  assert int(calls()) == expected
  assert readFile(journalPath) == before
  check(file.snapshot.value, root, size)
  let context = file.snapshotContext.value
  assert context == (if schema == StorageSchema.FullStateV1: @[16'u8] else: @[])
  assert file.close == FileError.None and seed.close == RepositoryError.None
  check(held, root, size)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Only the exact test-owned epoch is retired.
  else:
    var nativePath = path
    assert posix.unlink(nativePath.toCString()) == 0
try:
  for managed in [false, true]:
    # Repeat matching schemas and leaf representations without treating timing noise as a verdict.
    for schema in [StorageSchema.FullNodesV1, StorageSchema.FullStateV1]:
      for size in [16, 64]:
        for sample in 0..<3:
          scenario(managed, schema, size, sample)
except:
  quit(2)
echo "PASS storage replay cost: both layouts/schemas, single integrity passes, unchanged bytes and retained maps"
