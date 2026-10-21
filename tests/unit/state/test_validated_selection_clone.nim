# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque complete selections materialize independent bounded memory owners without hashing trusted data again.
# @@Verification={"arc":"validated_selection_clone_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[node_repository, node_records, full_state_trie]
import ../../../src/codec/[bounded, state_trie]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Use real primitive behavior while observing actual hash attempts.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## A trusted materialization must perform no hidden hash or verification calls.
proc cycle(selection: RepositorySelection, limits: RepositoryLimits) =
  ## Detached physical tables and payloads retire after each independent cloned update handle.
  var cloned = cloneRepositorySelection(selection, limits).value
  assert cloned.snapshot.value.storedNodes == selection.retainedNodes
  assert cloned.close == RepositoryError.None
proc main() =
  ## Retain an old and current complete root, drop an intermediate map and preserve exact inherited graph policy.
  reset(0)
  let limits = storageLimits()
  let first = storageTrie(7)
  let second = storageTrie(8)
  let third = storageTrie(10)
  var source = newNodeRepository(limits)
  let old = source.publish(source.snapshot.value, exportFullTrie(first,
      limits.codec.records).value).value
  let middle = source.publish(old, exportTrieChanges(first, second,
      limits.codec.records).value).value
  let head = source.publish(middle, exportTrieChanges(second, third,
      limits.codec.records).value).value
  let plan = selectRepositoryRoots(head, [old.commitment.root, head.commitment.root], ElementLimit(2)).value
  assert source.close == RepositoryError.None
  reset(0)
  var cloned = cloneRepositorySelection(plan, limits).value
  assert calls() == 0
  let selected = cloned.snapshot.value
  assert uint64(selected.generation) == uint64(head.generation) and selected.storedNodes <
      head.storedNodes
  assert restoreHistoricalStateEntries(selected, old.commitment.root,
      limits.codec.trie).value.len == 2
  assert restoreHistoricalStateEntries(selected, middle.commitment.root, limits.codec.trie).error ==
      RepositoryError.MissingNode
  assert cloned.publish(head, exportTrieChanges(third, third, limits.codec.records).value).error ==
      RepositoryError.StaleView
  assert cloned.close == RepositoryError.None
  var changed = limits
  changed.codec.trie.items = ElementLimit(uint64(limits.codec.trie.items)+1)
  assert cloneRepositorySelection(plan, changed).error == RepositoryError.PolicyMismatch
  changed = limits
  changed.records = ElementLimit(uint64(plan.retainedNodes-1))
  assert cloneRepositorySelection(plan, changed).error == RepositoryError.LimitExceeded
  assert cloneRepositorySelection(default(RepositorySelection), limits).error ==
      RepositoryError.Uninitialized
  reset(0)
  for iteration in 0..<10: cycle(plan, limits)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(plan, limits)
  let after = getOccupiedMem()
  assert before == after and calls() == 0
  recordArcRelease("validated_selection_clone", 1000, before, after)
main()
echo "PASS validated selection clone: no rehash, detached tables, exact policy, retained roots and ARC release"
