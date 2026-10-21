# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Serialized publication retains every integrity, routing, identity and atomic ownership boundary.
# @@Verification={"arc": "storage_encoded_publication_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the existing observer while retaining genuine primitive implementations.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual physical record integrity attempts independently of graph traversal.
proc cycle() =
  ## Raw and serialized admission must agree on complete maps, while serialized records hash once.
  let limits = storageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  let full = exportFullTrie(a, limits.codec.records).value
  let delta = exportTrieChanges(a, b, limits.codec.records).value
  var wire = encodeTrieExport(full, limits.codec).value
  let changed = encodeTrieExport(delta, limits.codec).value
  var owner = newNodeRepository(limits)
  let empty = owner.snapshot.value
  reset(0)
  let first = owner.publishEncoded(empty, wire).value
  assert int(calls()) == full.records.len
  assert restoreStateEntries(first, a.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  reset(0)
  let next = owner.publishEncoded(first, changed).value
  assert int(calls()) == delta.records.len
  assert owner.publishEncoded(first, changed).error == RepositoryError.StaleView
  assert owner.publishEncoded(next, wire).error == RepositoryError.BaseMismatch
  for stop in 0..<changed.len:
    # Truncated serialized revisions cannot alter generation, root or physical inventory.
    assert owner.publishEncoded(next, changed.toOpenArray(0, stop-1)).error != RepositoryError.None
    assert uint64(owner.snapshot.value.generation) == 2
  var corrupt = changed
  corrupt[corrupt.len-1] = corrupt[corrupt.len-1] xor 1
  assert owner.publishEncoded(next, corrupt).error == RepositoryError.InvalidRecords
  var reversed = full
  let left = reversed.records[2].left
  reversed.records[2].left = reversed.records[2].right
  reversed.records[2].right = left
  reversed.records[2].digest = hashStateNode(encodeStateBranch(reversed.records[2].left,
    reversed.records[2].right)).value
  reversed.root = StateRoot(array[32, byte](reversed.records[2].digest))
  var blank = newNodeRepository(limits)
  let malformed = encodeTrieExport(reversed, limits.codec).value
  assert blank.publishEncoded(blank.snapshot.value, malformed).error == RepositoryError.InvalidGraph
  var raw = decodeTrieExport(wire, limits.codec).value
  raw.records[0].payload[0] = 99
  assert blank.publish(blank.snapshot.value, raw).error == RepositoryError.InvalidRecords
  var narrow = limits
  narrow.records = ElementLimit(2)
  var bounded = newNodeRepository(narrow)
  assert bounded.publishEncoded(bounded.snapshot.value, wire).error == RepositoryError.LimitExceeded
  for index in 0..<wire.len:
    wire[index] = 0 # Returned owners retain no caller byte aliases.
  assert owner.close == RepositoryError.None
  assert blank.close == RepositoryError.None and bounded.close == RepositoryError.None
  assert restoreStateEntries(first, a.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  assert restoreStateEntries(next, b.commitment.root, limits.codec.trie).value[0].value == @[8'u8]
for iteration in 0..<10:
  cycle() # Warm exact success/refusal lifetime paths before accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Every decoded/raw transport and immutable view must retire without a trust token escaping.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_encoded_publication", 1000, before, after)
echo "PASS storage encoded publication: single hashing, strict admission, atomic refusal, ownership and ARC"
