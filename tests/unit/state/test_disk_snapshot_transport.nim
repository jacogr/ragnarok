# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot exports and trusted leaf extraction avoid hash work and isolate mutable transport bytes.
import std/[assertions, syncio]
import ../../support/storage_samples
import ../../../src/state/store
import ../../../src/storage/[full_state_trie, node_records, node_repository]
import ../../../src/codec/[state_trie, state_layout, bounded]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashing while observing transport-only calls.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count cryptographic work independently of serialized record counts.
proc run() =
  ## Only independently trusted roots may extract full mappings; callers own every returned byte.
  let limits = storageLimits()
  let policy = StateStoreLimits(trie: limits.codec.trie, writes: ElementLimit(4),
    writeValueBytes: ByteLimit(64))
  var state = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8]),
    StateEntry(key: storageKey(128))], policy).value
  let first = state.snapshot.value
  var repository = newNodeRepository(limits)
  reset(1)
  let full = first.exportStateSnapshot(limits.codec.records)
  assert full.error == TrieError.None and calls() == 0
  assert default(StateStoreSnapshot).exportStateSnapshot(limits.codec.records).error ==
      TrieError.Uninitialized
  assert exportStateChanges(first, default(StateStoreSnapshot), limits.codec.records).error ==
      TrieError.Uninitialized
  assert first.exportStateSnapshot(TrieExportLimits()).error == TrieError.LimitExceeded
  reset(0)
  let published = repository.publish(repository.snapshot.value, full.value).value
  let changed = state.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put,
    value: @[8'u8])]).value
  reset(1)
  let delta = exportStateChanges(first, changed, limits.codec.records).value
  assert delta.records.len == 2 and calls() == 0
  var entries = published.restoreStateEntries(first.commitment.root, limits.codec.trie).value
  assert entries.len == 2 and calls() == 0
  var wrong = default(array[32, byte])
  wrong[0] = 42
  assert published.restoreStateEntries(StateRoot(wrong), limits.codec.trie).error ==
      RepositoryError.RootMismatch
  var narrow = limits.codec.trie
  narrow.items = ElementLimit(1)
  assert published.restoreStateEntries(first.commitment.root, narrow).error ==
      RepositoryError.LimitExceeded
  # Mutating every detached leaf cannot alter repository data or either immutable snapshot.
  for i in 0..<entries.len:
    if entries[i].value.len > 0: entries[i].value[0] = 99
  assert first.lookup(storageKey(0)).value.bytes == @[7'u8]
  reset(0)
  let second = repository.publish(published, delta).value
  let restored = second.restoreFullTrie(changed.commitment.root,
    FullStateTrieLimits(trie: limits.codec.trie)).value
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert restored.lookup(storageKey(128)).value.byteLength == 0
  assert repository.close == RepositoryError.None
run()
echo "PASS disk snapshot transport: bounded detached deltas, trusted leaves and zero hash work"
