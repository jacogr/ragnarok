# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## White-box sharing plus real primitive-call evidence; no observer API enters production.

# @@Verification={"arc": "full_state_trie_arc_release"}

import std/[assertions, syncio]
import ../../support/arc_evidence
include ../../../src/storage/full_state_trie

proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset primitive observation and optionally refuse every hash.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse after an exact successful hash prefix, including long-value encoding hashes.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive attempts rather than inferred cached metadata.

proc policy(nodes = 1000'u64): FullStateTrieLimits =
  ## Two leaves diverging at the last bit can require exactly 250 nonempty nodes.
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(132), nodes: TrieNodeLimit(nodes)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(132))

proc key(first, last: byte): StateKey =
  ## Select both root branches or the deepest possible shared-prefix topology.
  var raw = default(array[31, byte])
  raw[0] = first
  raw[30] = last
  StateKey(raw)

proc cycle() =
  ## All new/retained owners retire after early/late hash refusal and independent successful forks.
  fail(0)
  let source = newFullStateTrie([StateEntry(key: key(0, 0), value: @[1'u8]),
    StateEntry(key: key(128, 0), value: @[2'u8])], policy()).value
  let retained = source.lookup(key(0, 0)).value
  let original = source.data
  assert original != nil
  let root = original.root
  assert root != nil
  let left = root.left
  let changes = [TrieWrite(key: key(128, 0), kind: TrieWriteKind.Put, value: newSeq[byte](33)),
    TrieWrite(key: key(192, 0), kind: TrieWriteKind.Put, value: @[4'u8])]
  fail(0)
  let changed = source.apply(changes).value
  let attempts = hashCalls()
  assert attempts == 5 # Long raw value, two new leaves, new right branch, new root; left leaf is reused.
  let revised = changed.data
  assert revised != nil
  let updated = revised.root
  assert updated != nil
  let right = updated.right
  assert right != nil
  assert updated != root and updated.left == left
  assert right.left != root.right
  assert root.left == left and retained.bytes == @[1'u8]
  for prefix in 0..<int(attempts):
    failAfter(cint(prefix))
    assert source.apply(changes).error == TrieError.BackendFailure
    assert hashCalls() == cint(prefix+1)
    assert original.root == root and root.left == left
    assert source.lookup(key(128, 0)).value.bytes == @[2'u8]
    assert source.lookup(key(192, 0)).error == TrieError.MissingKey
    assert retained.bytes == @[1'u8]
  fail(1)
  assert sameTrieRevision(source, source.apply([]).value) and hashCalls() == 0
  assert sameTrieRevision(source, source.apply([TrieWrite(key: key(64, 0),
    kind: TrieWriteKind.Delete)]).value) and hashCalls() == 0
  assert source.apply([changes[0], changes[0]]).error == TrieError.DuplicateKey and hashCalls() == 0
  # Collapse to a cached old leaf requires no hash; it must still preserve all earlier versions.
  let collapsed = source.apply([TrieWrite(key: key(128, 0), kind: TrieWriteKind.Delete)]).value
  let single = collapsed.data
  assert single != nil
  assert single.root == left and hashCalls() == 0
  assert collapsed.commitment.nodes == 1 and source.commitment.nodes == 3
  fail(0)
  assert array[32, byte](source.apply(changes).value.commitment.root) == array[32, byte](
      changed.commitment.root)

proc preflight() =
  ## Final topology and all payload/count policies reject before touching the hash backend.
  for nodes in [1'u64, 249'u64, 250'u64]:
    fail(0)
    let source = newFullStateTrie([StateEntry(key: key(0, 0))], policy(nodes)).value
    fail(1)
    let next = source.apply([TrieWrite(key: key(0, 1), kind: TrieWriteKind.Put)])
    if nodes < 250:
      assert next.error == TrieError.LimitExceeded and hashCalls() == 0 # Count exact topology before hashing.
    else:
      assert next.error == TrieError.BackendFailure and hashCalls() == 1 # Exact budget reaches the backend.
    assert source.commitment.nodes == 1
  for mode in 0..<4:
    fail(0)
    var limit = policy()
    if mode == 0: limit.trie.items = ElementLimit(1) # Reject exact final entry count.
    elif mode == 1: limit.trie.perValue = ByteLimit(1) # Reject a single oversized caller value.
    elif mode == 2: limit.trie.totalValueBytes = ByteLimit(1) # Reject aggregate final value bytes.
    else: limit.writeValueBytes = ByteLimit(1) # Reject aggregate borrowed mutation bytes.
    let source = newFullStateTrie([StateEntry(key: key(0, 0), value: @[1'u8])], limit).value
    fail(1)
    assert source.apply([TrieWrite(key: key(128, 0), kind: TrieWriteKind.Put,
      value: @[2'u8, 3])]).error == TrieError.LimitExceeded
    assert hashCalls() == 0 and source.commitment.entries == 1
  fail(1)
  let entries = [StateEntry(key: key(0, 0)), StateEntry(key: key(0, 1))]
  assert newFullStateTrie(entries, policy(249)).error == TrieError.LimitExceeded
  assert hashCalls() == 0 # Construction uses the same exact no-hash topology preflight.
  assert newFullStateTrie([entries[0], entries[0]], policy()).error == TrieError.DuplicateKey
  assert hashCalls() == 0
  for prefix in 0..<3:
    failAfter(cint(prefix))
    let initial = [StateEntry(key: key(0, 0)), StateEntry(key: key(128, 0))]
    assert newFullStateTrie(initial, policy()).error == TrieError.BackendFailure
    assert hashCalls() == cint(prefix+1) # Constructor rollback includes both child and root failure.
  fail(0)

preflight()
# Warm the exact isolated workload before measuring success, failure and retained-owner retirement.
for i in 0..<25: cycle()
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Each cycle drops both complete graphs and every partial failed candidate.
let after = getOccupiedMem()
assert before == after
recordArcRelease("full_state_trie_private", 1000, before, after)
fail(0)
echo "PASS full state trie internals: shared subtrees, affected hashes, preflight, rollback and ARC release"
