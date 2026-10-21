# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private record sharing must preserve independent forks and fully detached mutable public transports.
# @@Verification={"arc": "storage_record_owners_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
proc check(view: RepositoryView, value: byte) =
  ## Both complete entries remain exact under the selected root, independent of table sharing.
  let entries = restoreStateEntries(view, view.commitment.root, storageLimits().codec.trie).value
  assert entries.len == 2
  assert entries[0].value == @[value] and entries[1].value == @[9'u8]
proc detachedClone(limits: RepositoryLimits): NodeRepository =
  ## Return a clone after the source owner, source views and selection all retire at this boundary.
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits)
  let first = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.codec.records).value).value
  let next = source.publish(first, exportTrieChanges(a, b, limits.codec.records).value).value
  let selection = selectRepositoryRoots(next, [first.commitment.root, next.commitment.root],
      ElementLimit(2)).value
  result = cloneRepositorySelection(selection, limits).value
  assert source.close == RepositoryError.None
proc cycle() =
  ## Separate mutable handles share only immutable predecessors; every public byte array stays detached.
  let limits = storageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  let c = storageTrie(10)
  let d = storageTrie(11)
  var alone = detachedClone(limits)
  let aloneView = alone.snapshot.value
  check(aloneView, 8)
  assert restoreHistoricalStateEntries(aloneView, a.commitment.root, limits.codec.trie).value[
      0].value == @[7'u8]
  assert alone.close == RepositoryError.None
  check(aloneView, 8) # The cloned table alone must keep its immutable cells alive.
  var transport = exportFullTrie(a, limits.codec.records).value
  var owner = newNodeRepository(limits)
  let first = owner.publish(owner.snapshot.value, transport).value
  let changedLeaf = transport.records[0].digest
  let sharedLeaf = transport.records[1].digest
  var fork = owner
  let next = fork.publish(first, exportTrieChanges(a, b, limits.codec.records).value).value
  transport.records[0].payload[0] = 99
  check(first, 7)
  check(owner.snapshot.value, 7)
  check(next, 8)
  var bytes = next.lookupNode(sharedLeaf).value
  bytes.payload[0] = 99
  assert first.lookupNode(sharedLeaf).value.payload == @[9'u8]
  assert next.lookupNode(sharedLeaf).value.payload == @[9'u8]
  var entries = restoreStateEntries(first, first.commitment.root, limits.codec.trie).value
  entries[0].value[0] = 88
  assert first.lookupNode(changedLeaf).value.payload == @[7'u8]
  let selected = selectRepositoryRoots(next, [first.commitment.root, next.commitment.root],
      ElementLimit(2)).value
  var detached = exportRepositoryImage(selected, limits.codec.records, ElementLimit(2)).value
  for index in 0..<detached.collection.records.len:
    if detached.collection.records[index].kind == TrieRecordKind.Leaf:
      detached.collection.records[index].payload[0] = 77 # Exported transport cannot mutate any shared cell.
  check(first, 7)
  check(next, 8)
  var cloned = cloneRepositorySelection(selected, limits).value
  let clonedView = cloned.snapshot.value
  assert cloned.publish(next, exportTrieChanges(b, c, limits.codec.records).value).error ==
      RepositoryError.StaleView
  let ownChild = owner.publish(first, exportTrieChanges(a, c, limits.codec.records).value).value
  let forkChild = fork.publish(next, exportTrieChanges(b, d, limits.codec.records).value).value
  let cloneChild = cloned.publish(clonedView, exportTrieChanges(b, a,
      limits.codec.records).value).value
  check(ownChild, 10)
  check(forkChild, 11)
  check(cloneChild, 7)
  check(first, 7)
  check(next, 8)
  assert restoreHistoricalStateEntries(clonedView, first.commitment.root, limits.codec.trie).value[
      0].value == @[7'u8]
  assert owner.close == RepositoryError.None
  assert fork.close == RepositoryError.None
  assert cloned.close == RepositoryError.None
  check(first, 7)
  check(next, 8)
  check(ownChild, 10)
  check(forkChild, 11)
  check(cloneChild, 7)
for iteration in 0..<25:
  cycle() # Warm all explicit ownership and detached transport paths.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Shared cells must retire exactly after the final table/view releases them.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_record_owners", 1000, before, after)
echo "PASS storage record owners: independent forks, detached transports, retained views and ARC"
