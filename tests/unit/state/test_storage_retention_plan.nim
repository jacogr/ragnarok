# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit retention plans count shared physical records and preserve immutable source ownership.
# @@Verification={"arc": "storage_retention_plan_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[records as node_records, repository as node_repository]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc cycle() =
  ## Three revisions share one leaf; selecting first/last retains five of seven physical records.
  let limits = storageLimits()
  let first = storageTrie(7)
  let middle = storageTrie(8)
  let last = storageTrie(10)
  var repository = newNodeRepository(limits)
  let a = repository.publish(repository.snapshot.value, exportFullTrie(first,
      limits.codec.records).value).value
  let b = repository.publish(a, exportTrieChanges(first, middle, limits.codec.records).value).value
  let c = repository.publish(b, exportTrieChanges(middle, last, limits.codec.records).value).value
  let roots = [first.commitment.root, last.commitment.root]
  let plan = selectRepositoryRoots(c, roots, ElementLimit(2)).value
  assert plan.initialized and plan.matches(c) and not plan.matches(a)
  assert plan.retainedNodes == 5 and plan.reclaimableNodes == 2
  assert plan.retainedValueBytes == 3 and plan.reclaimableValueBytes == 1
  assert plan.retainedRoots.len == 2
  var copied = plan.retainedRoots
  copied[0] = default(StateRoot)
  assert array[32, byte](plan.retainedRoots[0]) == array[32, byte](first.commitment.root)
  let all = selectRepositoryRoots(c, [first.commitment.root, middle.commitment.root,
    last.commitment.root, last.commitment.root], ElementLimit(4)).value
  assert all.retainedRoots.len == 3 and all.retainedNodes == 7
  assert all.reclaimableNodes == 0 and all.reclaimableValueBytes == 0
  let reversed = selectRepositoryRoots(c, [last.commitment.root, default(StateRoot),
    first.commitment.root, middle.commitment.root], ElementLimit(4)).value
  assert reversed.retainedNodes == all.retainedNodes and reversed.retainedValueBytes ==
      all.retainedValueBytes
  assert reversed.retainedRoots.len == 4 # Empty roots between overlapping nonempty roots cannot retain stale scratch.
  let current = selectRepositoryRoots(c, [last.commitment.root], ElementLimit(1)).value
  assert current.retainedNodes == 3 and current.reclaimableNodes == 4
  assert selectRepositoryRoots(c, roots, ElementLimit(1)).error == RepositoryError.LimitExceeded
  assert selectRepositoryRoots(c, [], ElementLimit(0)).error == RepositoryError.RootMismatch
  assert selectRepositoryRoots(c, [first.commitment.root], ElementLimit(1)).error ==
      RepositoryError.RootMismatch
  var missing = default(array[32, byte])
  missing[0] = 42
  assert selectRepositoryRoots(c, [last.commitment.root, StateRoot(missing)], ElementLimit(
      2)).error == RepositoryError.MissingNode
  let empty = selectRepositoryRoots(c, [last.commitment.root, default(StateRoot)], ElementLimit(2)).value
  assert empty.retainedNodes == current.retainedNodes and empty.retainedRoots.len == 2
  assert selectRepositoryRoots(default(RepositoryView), roots, ElementLimit(2)).error ==
      RepositoryError.Uninitialized
  assert not default(RepositorySelection).initialized and not default(RepositorySelection).matches(c)
  let later = storageTrie(12)
  let advanced = repository.publish(c, exportTrieChanges(last, later,
      limits.codec.records).value).value
  assert not plan.matches(advanced) and plan.matches(c) and plan.retainedNodes == 5
  assert repository.close == RepositoryError.None
  assert plan.matches(c) and plan.retainedNodes == 5 and plan.retainedRoots.len == 2
  var blank = newNodeRepository(limits)
  let zero = selectRepositoryRoots(blank.snapshot.value, [default(StateRoot)], ElementLimit(1)).value
  assert zero.retainedNodes == 0 and zero.reclaimableNodes == 0 and zero.retainedValueBytes == 0
  assert blank.close == RepositoryError.None
for iteration in 0..<25: cycle() # Warm every accepted and refused ownership path.
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Immutable plans and copied root arrays retire without cycles.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_retention_plan", 1000, before, after)
echo "PASS storage retention plan: root union, shared bytes, bounds, exact owners and ARC"
