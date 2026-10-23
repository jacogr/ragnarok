# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable root inventories cover large distinct/duplicate sets, tight bounds, source retirement and late refusal.
# @@Verification={"arc": "storage_root_inventory_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_root_samples, arc_evidence]
import ../../../src/storage/[node_repository, node_records]
import ../../../src/codec/[state_layout, state_trie, bounded]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Selection must not hash immutable already-admitted records, even with the backend refusing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual primitive attempts rather than assuming graph traversal never hashes.

proc sameRoots(left, right: seq[StateRoot]): bool =
  ## Root sequence equality includes caller order and every byte of each complete identity.
  if left.len != right.len: return false
  for index in 0..<left.len:
    if array[32, byte](left[index]) != array[32, byte](right[index]): return false
  true

proc exercise(source: RootFixture) =
  ## Reversed inventories with early/late duplicates preserve first occurrences and exact source ownership.
  var input: seq[StateRoot] = @[]
  var expected: seq[StateRoot] = @[]
  for offset in 0..<source.roots.len:
    let root = source.roots[source.roots.len-1-offset]
    input.add(root)
    input.add(root) # Adjacent equal identities cannot add retained roots or physical records.
    expected.add(root)
  input.add(source.roots[0])
  input.add(source.roots[source.roots.len-1])
  reset(1)
  let selected = selectRepositoryRoots(source.view, input, ElementLimit(input.len)).value
  assert hashCalls() == 0
  assert sameRoots(selected.retainedRoots, expected)
  assert selected.retainedNodes == source.roots.len-1 and selected.reclaimableNodes == 0
  assert selected.retainedValueBytes == uint64((source.roots.len-1)*2)
  assert selectRepositoryRoots(source.view, input, ElementLimit(input.len-1)).error ==
      RepositoryError.LimitExceeded
  assert selectRepositoryRoots(source.view, [], ElementLimit(0)).error ==
      RepositoryError.RootMismatch
  assert selectRepositoryRoots(source.view, [source.roots[0]], ElementLimit(1)).error ==
      RepositoryError.RootMismatch
  var unknown = default(array[32, byte])
  unknown[0] = 255
  assert selectRepositoryRoots(source.view, [StateRoot(unknown)], ElementLimit(1)).error ==
      RepositoryError.RootMismatch
  assert selectRepositoryRoots(source.view, [source.view.commitment.root, StateRoot(unknown)],
    ElementLimit(2)).error == RepositoryError.MissingNode
  assert hashCalls() == 0 and selected.matches(source.view)
  input[0] = default(StateRoot)
  input.setLen(0)
  var detached = selected.retainedRoots
  detached[0] = default(StateRoot)
  assert sameRoots(selected.retainedRoots, expected) # Neither borrowed nor returned storage can change the plan.
  let repeated = selectRepositoryRoots(source.view, [source.view.commitment.root,
    source.view.commitment.root], ElementLimit(2)).value
  assert repeated.retainedRootCount == 1 and repeated.retainedNodes == 1
  reset(0)
  var clone = cloneRepositorySelection(selected, source.limits).value
  let independent = clone.snapshot.value
  assert clone.close == RepositoryError.None
  for root in source.roots:
    let entries = restoreHistoricalStateEntries(independent, root, source.limits.codec.trie).value
    assert entries.len == (if array[32, byte](root) == default(array[32, byte]): 0 else: 1)

proc detached(): RepositorySelection =
  ## The selection outlives its fixture, root descriptor storage and closed mutable repository owner.
  let source = rootFixture(3)
  selectRepositoryRoots(source.view, source.roots, ElementLimit(source.roots.len)).value

let beforeLarge = getOccupiedMem()
block:
  let source = rootFixture(4096)
  exercise(source)
assert getOccupiedMem() == beforeLarge
for warmup in 0..<10: exercise(rootFixture(3)) # Warm the exact scoped success/refusal paths.
let before = getOccupiedMem()
for iteration in 0..<1000: exercise(rootFixture(3))
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_root_inventory", 1000, before, after)
let held = detached()
assert held.retainedRootCount == 4 and held.retainedNodes == 3
echo "PASS storage root inventory: scalable stable roots, complete unions, quota, no hashes and ARC"
