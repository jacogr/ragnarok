# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded pins remain independent across catalog copies, repository revisions and close.
# @@Verification={"arc": "storage_retention_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/revision_retention
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie

proc cycle() =
  ## Check count refusals, opaque identity, explicit release and acyclic retained ownership.
  let limits = storageLimits()
  var repository = newNodeRepository(limits)
  let initial = storageTrie()
  let view = repository.publish(repository.snapshot.value,
    exportFullTrie(initial, limits.codec.records).value).value
  var catalog = newRevisionRetention(ElementLimit(2))
  assert catalog.opened and catalog.len == 0
  assert catalog.retain(default(RepositoryView)).error == RetentionError.InvalidView
  let first = catalog.retain(view).value
  let second = catalog.retain(view).value
  assert catalog.len == 2
  assert catalog.retain(view).error == RetentionError.LimitExceeded
  assert catalog.lookup(default(RetentionToken)).error == RetentionError.InvalidToken
  assert catalog.release(default(RetentionToken)) == RetentionError.InvalidToken
  var copied = catalog
  let held = catalog.lookup(first).value
  assert catalog.release(first) == RetentionError.None and catalog.len == 1
  assert catalog.release(first) == RetentionError.MissingToken
  assert catalog.lookup(first).error == RetentionError.MissingToken
  assert copied.len == 2 and copied.lookup(first).error == RetentionError.None
  let third = catalog.retain(view).value
  assert copied.lookup(third).error == RetentionError.MissingToken
  assert copied.release(third) == RetentionError.MissingToken
  assert copied.len == 2 and catalog.len == 2
  # Equal generation/root metadata is not sufficient to manufacture pin membership.
  var foreign = newRevisionRetention(ElementLimit(1))
  let other = foreign.retain(view).value
  assert catalog.lookup(other).error == RetentionError.MissingToken
  assert foreign.lookup(first).error == RetentionError.MissingToken
  let changed = initial.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put,
    value: @[11'u8])]).value
  let next = repository.publish(view, exportTrieChanges(initial, changed,
    limits.codec.records).value).value
  assert uint64(next.generation) == 2
  assert repository.close == RepositoryError.None
  assert catalog.lookup(second).value.commitment.entries == 2
  assert catalog.close == RetentionError.None and not catalog.opened
  assert catalog.close == RetentionError.Uninitialized
  assert catalog.retain(view).error == RetentionError.Uninitialized
  assert catalog.lookup(second).error == RetentionError.Uninitialized
  assert catalog.release(second) == RetentionError.Uninitialized
  assert held.restoreFullTrie(initial.commitment.root,
    FullStateTrieLimits(trie: limits.codec.trie)).value.lookup(storageKey(0)).value.bytes == @[7'u8]
  assert copied.close == RetentionError.None and foreign.close == RetentionError.None
  # Zero/default catalogs are distinct; neither can silently accept a view.
  var zero = newRevisionRetention(ElementLimit(0))
  assert zero.retain(held).error == RetentionError.LimitExceeded and zero.len == 0
  discard zero.close
  var absent = default(RevisionRetention)
  assert absent.retain(held).error == RetentionError.Uninitialized
  assert absent.lookup(first).error == RetentionError.Uninitialized

for i in 0..<25: cycle() # Warm the exact slot ownership and restore paths.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Every token, copied catalog and retained revision retires acyclically.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_retention", 1000, before, after)
echo "PASS storage retention: bounded explicit pins, exact tokens, catalog forks, retained views and ARC"
