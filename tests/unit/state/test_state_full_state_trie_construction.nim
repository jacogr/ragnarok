# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct complete-map construction preserves input ownership, error precedence and pre-hash ceilings.
# @@Verification={"arc": "full_state_trie_construction_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Real primitive refusal detects accidental hashing during bounded preflight.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Exact calls distinguish final leaf hashing from temporary construction work.
proc key(index: int): StateKey =
  ## Long shared prefixes exercise the constructor's deepest initial topology.
  var raw = default(array[31, byte])
  raw[29] = byte(index shr 8)
  raw[30] = byte(index and 255)
  StateKey(raw)
proc policy(): FullStateTrieLimits =
  ## Complete-map ceilings permit construction while both mutation ceilings stay zero.
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(65), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(16640), nodes: TrieNodeLimit(20000)))
proc fixture(count, size: int): seq[StateEntry] =
  ## Reverse order separates borrowed source positions from sorted topology positions.
  result = newSeq[StateEntry](count)
  for index in 0..<count:
    var bytes = newSeq[byte](size)
    for offset in 0..<size: bytes[offset] = byte((index+offset) and 255)
    result[count-1-index] = StateEntry(key: key(index), value: bytes)
proc construction(count, size: int) =
  ## Independent complete-map commitments precede the observed constructor and payload mutation.
  var entries = fixture(count, size)
  reset(0)
  let expected = stateTrieRoot(entries, policy().trie).value
  reset(0)
  let trie = newFullStateTrie(entries, policy()).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](expected.root)
  assert trie.commitment.entries == expected.entries and trie.commitment.nodes == expected.nodes
  assert uint64(calls()) == expected.nodes+(if size > 32: uint64(count) else: 0'u64)
  for index in 0..<count:
    let found = trie.lookup(key(index)).value
    assert found.byteLength == size
    if size > 0:
      assert found.bytes[0] == byte(index)
      entries[count-1-index].value[0] = 255
      assert found.bytes[0] == byte(index) # Final immutable leaves own bytes independently.
  entries.setLen(0)
  assert trie.commitment.entries == count
  assert trie.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Put)]).error ==
      TrieError.LimitExceeded
proc refused(entries: openArray[StateEntry], limits: FullStateTrieLimits, reason: TrieError) =
  ## Every refused preflight owns no completed trie and makes zero primitive calls.
  reset(1)
  assert newFullStateTrie(entries, limits).error == reason and calls() == 0
proc boundaries() =
  ## Combined invalidities preserve the original item, payload, duplicate then node ordering.
  let duplicate = [StateEntry(key: key(0), value: @[1'u8]), StateEntry(key: key(0), value: @[2'u8])]
  var limits = policy()
  limits.trie.items = ElementLimit(1)
  refused(duplicate, limits, TrieError.LimitExceeded)
  limits = policy()
  limits.trie.perValue = ByteLimit(0)
  refused(duplicate, limits, TrieError.LimitExceeded)
  limits = policy()
  limits.trie.totalValueBytes = ByteLimit(1)
  refused(duplicate, limits, TrieError.LimitExceeded)
  limits = policy()
  limits.trie.nodes = TrieNodeLimit(0)
  refused(duplicate, limits, TrieError.DuplicateKey)
  refused([duplicate[0]], limits, TrieError.LimitExceeded)
  reset(1)
  assert newFullStateTrie([], default(FullStateTrieLimits)).value.commitment.nodes == 0
  assert calls() == 0
  limits = policy()
  reset(0)
  let reference = stateTrieRoot(fixture(2, 33), limits.trie).value
  limits.trie.nodes = TrieNodeLimit(reference.nodes-1)
  refused(fixture(2, 33), limits, TrieError.LimitExceeded)
  limits.trie.nodes = TrieNodeLimit(reference.nodes)
  reset(1)
  assert newFullStateTrie(fixture(2, 33), limits).error == TrieError.BackendFailure
  assert calls() == 1 # Accepted quotas reach the actual provider and propagate refusal.
  reset(0)
  assert newFullStateTrie(fixture(2, 33), limits).value.commitment.nodes == reference.nodes
boundaries()
for count in [0, 1, 2, 17, 65]:
  for size in [0, 32, 33, 256]: construction(count, size)
reset(0)
construction(2, 33) # Warm the same allocator/compiler paths before exact repeated lifetime evidence.
let before = getOccupiedMem()
for cycle in 0..<1000: construction(2, 33)
let after = getOccupiedMem()
assert before == after
recordArcRelease("state_full_state_trie_construction", 1000, before, after)
echo "PASS full state trie construction: direct borrowed maps, independent roots, bounded preflight and owned values"
