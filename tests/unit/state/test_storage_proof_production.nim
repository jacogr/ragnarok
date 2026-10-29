# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete revisions produce exact bounded detached paths that verify against independent full-map roots.
# @@Verification={"arc": "storage_proof_production_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/state_proof
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse real hashing to distinguish free cached branch encoding from long-leaf preimages.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## A terminal long leaf is the producer's only possible cryptographic operation.
proc key(index: int): StateKey =
  ## Spread finite keys over both polarities and preserve every remaining serialized octet.
  var raw = default(array[31, byte])
  raw[0] = byte(index and 255)
  raw[30] = byte(index shr 8)
  StateKey(raw)
proc policy(): FullStateTrieLimits =
  ## Complete maps and subsequent historical forks retain explicit independent batch ceilings.
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(256), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(65536), nodes: TrieNodeLimit(10000)), writes: ElementLimit(256),
    writeValueBytes: ByteLimit(65536))
proc limits(): StateProofLimits =
  ## Generation and verification use the same maximum path domain and copied-value budget.
  StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256))
proc allocated(nodes, bytes: int): int =
  ## Public allocator calibration bounds a held proof to its exact node buffer and present value bytes.
  let before = getOccupiedMem()
  var expected = 0
  block:
    let buffer = newSeq[EncodedStateNode](nodes)
    expected += getOccupiedMem()-before
    assert buffer.len == nodes
  assert getOccupiedMem() == before
  block:
    let buffer = newSeq[byte](bytes)
    expected += getOccupiedMem()-before
    assert buffer.len == bytes
  assert getOccupiedMem() == before
  expected
proc check(trie: FullStateTrie, root: StateRoot, query: StateKey, present: bool, bytes: seq[byte]) =
  ## Generation uses cached branch hashes; the independent trusted root validates every produced link.
  reset(0)
  let baseline = getOccupiedMem()
  var outcome = trie.prove(query, limits())
  assert outcome.error == TrieError.None
  let attempts = calls()
  let retained = getOccupiedMem()-baseline
  let before = getOccupiedMem()
  var proof = outcome.takeValue
  assert outcome.error == TrieError.Uninitialized and getOccupiedMem() == before
  assert proof.nodes.len <= 249 and (proof.value == bytes or not present)
  assert retained == allocated(proof.nodes.len, proof.value.len)
  if proof.nodes.len > 0:
    let terminal = decodeStateNode(array[64, byte](proof.nodes[proof.nodes.len-1])).value.node
    assert attempts == (if terminal.kind == StateNodeKind.HashedLeaf: 1.cint else: 0.cint)
  else:
    assert attempts == 0
  let verified = verifyStateProof(root, query, proof, limits()).value
  assert verified.kind == (if present: StateLookupKind.Present else: StateLookupKind.Absent)
  if present: assert verified.bytes == bytes
  else: assert proof.value.len == 0 # Different-key absence never exports a terminal leaf's raw value.
  if proof.value.len > 0: proof.value[0] = proof.value[0] xor 255
  proof.nodes.setLen(0)
  proof.value.setLen(0)
  if present:
    assert verified.bytes == bytes and trie.lookup(query).value.bytes == bytes
proc mappings() =
  ## Unsorted complete maps and present-empty/inline/long values agree with the independent root calculator.
  for count in [0, 1, 2, 65]:
    var entries: seq[StateEntry] = @[]
    for index in 0..<count:
      let size = [0, 32, 33, 256][index mod 4]
      var bytes = newSeq[byte](size)
      for offset in 0..<size: bytes[offset] = byte((index+offset) and 255)
      entries.add(StateEntry(key: key((count-1-index)*3), value: bytes))
    reset(0)
    let expected = stateTrieRoot(entries, policy().trie).value
    let trie = newFullStateTrie(entries, policy()).value
    for entry in entries: check(trie, expected.root, entry.key, true, entry.value)
    for query in [key(1), key(254), key(300)]: check(trie, expected.root, query, false, @[])
proc boundaries() =
  ## All path/value ceilings refuse before hashing; absent long leaves require no copied-value allowance.
  reset(0)
  assert default(FullStateTrie).prove(key(0), limits()).error == TrieError.Uninitialized
  let empty = newFullStateTrie([], policy()).value
  reset(1)
  assert empty.prove(key(0), default(StateProofLimits)).value.nodes.len == 0 and calls() == 0
  reset(0)
  let longTrie = newFullStateTrie([StateEntry(key: key(0), value: newSeq[byte](33))], policy()).value
  var small = limits()
  small.nodes = ElementLimit(0)
  reset(1)
  assert longTrie.prove(key(0), small).error == TrieError.LimitExceeded and calls() == 0
  small = limits()
  small.valueBytes = ByteLimit(32)
  assert longTrie.prove(key(0), small).error == TrieError.LimitExceeded and calls() == 0
  assert longTrie.prove(key(1), small).error == TrieError.BackendFailure and calls() == 1
  reset(0)
  small.valueBytes = ByteLimit(0)
  let absent = longTrie.prove(key(1), small).value
  assert absent.nodes.len == 1 and absent.value.len == 0 and calls() == 1
  assert verifyStateProof(longTrie.commitment.root, key(1), absent, small).value.kind ==
      StateLookupKind.Absent
  reset(0)
  var last = default(array[31, byte])
  last[30] = 1
  let deep = newFullStateTrie([StateEntry(key: default(StateKey)),
    StateEntry(key: StateKey(last), value: @[7'u8])], policy()).value
  small = limits()
  small.nodes = ElementLimit(248)
  reset(1)
  assert deep.prove(default(StateKey), small).error == TrieError.LimitExceeded and calls() == 0
  small.nodes = ElementLimit(249)
  assert deep.prove(default(StateKey), small).value.nodes.len == 249 and calls() == 0
  let zeroChild = deep.prove(key(128), StateProofLimits(nodes: ElementLimit(1))).value
  assert zeroChild.nodes.len == 1 and zeroChild.value.len == 0 and calls() == 0
  reset(0)
  assert verifyStateProof(deep.commitment.root, key(128), zeroChild, limits()).value.kind ==
      StateLookupKind.Absent
proc detached(): StateProof =
  ## Only detached proof bytes survive retirement of their source revision, entries and result wrapper.
  reset(0)
  var entries = @[StateEntry(key: key(0), value: @[1'u8, 2, 3])]
  let trie = newFullStateTrie(entries, policy()).value
  entries[0].value[0] = 99
  var outcome = trie.prove(key(0), limits())
  outcome.takeValue
proc history() =
  ## Old and new roots retain separate proofs after updates; mutation of a returned path cannot change either trie.
  reset(0)
  let old = newFullStateTrie([StateEntry(key: key(0), value: @[1'u8])], policy()).value
  let updated = old.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Put, value: @[2'u8])]).value
  check(old, old.commitment.root, key(0), true, @[1'u8])
  check(updated, updated.commitment.root, key(0), true, @[2'u8])
  let proof = old.prove(key(0), limits()).value
  assert verifyStateProof(updated.commitment.root, key(0), proof, limits()).error ==
      StateProofError.InvalidProof
proc refusedAndRecovered(trie: FullStateTrie) =
  ## Refusal after a branch descriptor is written retires private output, then the same source proves successfully.
  reset(1)
  assert trie.prove(key(0), limits()).error == TrieError.BackendFailure and calls() == 1
  reset(0)
  let proof = trie.prove(key(0), limits()).value
  let checked = verifyStateProof(trie.commitment.root, key(0), proof, limits()).value
  assert checked.kind == StateLookupKind.Present and checked.bytes.len == 33
mappings()
boundaries()
history()
let proof = detached()
assert proof.value == @[1'u8, 2, 3]
discard detached() # Warm the same complete producer/retirement path before exact lifetime evidence.
reset(0)
let recovering = newFullStateTrie([StateEntry(key: key(0), value: newSeq[byte](33)),
  StateEntry(key: key(128))], policy()).value
refusedAndRecovered(recovering)
let before = getOccupiedMem()
for cycle in 0..<1000:
  discard detached()
  refusedAndRecovered(recovering)
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_proof_production", 1000, before, after)
echo "PASS storage proof production: bounded paths, independent roots, cached branches and detached ownership"
