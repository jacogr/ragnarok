# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete roots and detached record paths witness bounded authenticated lookups and hostile proofs.
# @@Verification={"arc": "storage_state_proof_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Inject actual provider refusal and reset its exact attempt counter.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse after an exact successful node prefix, including the final long-value hash.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Verification work counts actual node/preimage hashes, independent of complete-map size.
type Fixture = object ## Separate complete-map root authority and detached full-hash physical records.
  root: StateRoot
  records: seq[TrieRecord]
proc limits(): StateProofLimits =
  ## The protocol path domain and a small raw-value policy are explicit caller ceilings.
  StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256))
proc key(index: int): StateKey =
  ## Leading ordinals cover both directions, while the last byte preserves distinct full identities.
  var raw = default(array[31, byte])
  raw[0] = byte(index and 255)
  raw[30] = byte(index shr 8)
  StateKey(raw)
proc fixture(entries: openArray[StateEntry]): Fixture =
  ## The independent flat calculator, rather than proof traversal, establishes the expected complete root.
  reset(0)
  let policy = StateTrieLimits(items: ElementLimit(256), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(65536), nodes: TrieNodeLimit(10000))
  let root = stateTrieRoot(entries, policy).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: policy)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  Fixture(root: root, records: exportFullTrie(trie, TrieExportLimits(records: TrieNodeLimit(10000),
    valueBytes: ByteLimit(65536))).value.records)
proc path(source: Fixture, query: StateKey): StateProof =
  ## A test-only linear physical-record producer follows complete child identities, independently of proof links.
  result = StateProof()
  var target = StateNodeHash(array[32, byte](source.root))
  var depth = 0
  while array[32, byte](target) != default(array[32, byte]):
    var found = false
    for record in source.records:
      if array[32, byte](record.digest) == array[32, byte](target):
        found = true
        if record.kind == TrieRecordKind.Leaf:
          result.nodes.add(encodeStateLeaf(record.key, record.payload, ByteLimit(256)).value)
          if array[31, byte](record.key) == array[31, byte](query): result.value = record.payload
          return # A terminal leaf is present or different-key absence; no other record is emitted.
        result.nodes.add(encodeStateBranch(record.left, record.right))
        assert depth < 248
        let raw = array[31, byte](query)
        target = if (raw[depth div 8] and byte(128 shr (depth mod 8))) ==
            0: record.left else: record.right
        inc depth
        break # Exactly one complete identity selects the next path record.
    assert found # Complete exported maps contain every nonempty physical child.
proc check(source: Fixture, query: StateKey, present: bool, expected: seq[byte]) =
  ## Each result binds the exact trusted root/query and distinguishes absent from present-empty.
  var proof = path(source, query)
  reset(0)
  let outcome = verifyStateProof(source.root, query, proof, limits())
  assert outcome.error == StateProofError.None
  let lookup = outcome.value
  assert array[32, byte](lookup.root) == array[32, byte](source.root)
  assert array[31, byte](lookup.key) == array[31, byte](query)
  assert lookup.kind == (if present: StateLookupKind.Present else: StateLookupKind.Absent)
  assert calls() == cint(proof.nodes.len+(if present and expected.len > 32: 1 else: 0))
  if present:
    assert lookup.bytes == expected
    if proof.value.len > 0: proof.value[0] = proof.value[
        0] xor 255 # Input mutation cannot alter retained proof evidence.
    var copied = lookup.bytes
    if copied.len > 0: copied[0] = copied[0] xor 255 # Returned mutable copies have separate backing storage.
    assert lookup.bytes == expected
  proof.nodes.setLen(0)
  proof.value.setLen(0)
  assert lookup.kind == (if present: StateLookupKind.Present else: StateLookupKind.Absent)
proc mappings() =
  ## Real finite maps exercise root/right full hashes, high-bit left hashes and inline/long values.
  for count in [0, 1, 2, 65]:
    var entries: seq[StateEntry] = @[]
    for index in 0..<count:
      let size = [0, 32, 33, 256][index mod 4]
      var bytes = newSeq[byte](size)
      for offset in 0..<size: bytes[offset] = byte((index+offset) and 255)
      entries.add(StateEntry(key: key(index*3), value: bytes))
    let source = fixture(entries)
    if count == 65:
      var highLeft = 0
      for record in source.records:
        if record.kind == TrieRecordKind.Branch and (array[32, byte](record.left)[0] and 128) != 0:
          inc highLeft # The following real inclusion checks must accept discarded high child bits.
      assert highLeft > 0
    for entry in entries: check(source, entry.key, true, entry.value)
    for query in [key(1), key(254), key(255), key(300)]:
      check(source, query, false, @[]) # These full keys are absent from every authored map.
proc hostile() =
  ## Every byte/path/value mutation must fail without returning any lookup authority.
  let query = key(0)
  let source = fixture([StateEntry(key: query, value: newSeq[byte](33)),
    StateEntry(key: key(128), value: @[9'u8])])
  let proof = path(source, query)
  assert proof.nodes.len == 2
  for index in 0..<proof.nodes.len:
    var changed = proof
    var raw = array[64, byte](changed.nodes[index])
    raw[63] = raw[63] xor 1
    changed.nodes[index] = EncodedStateNode(raw)
    reset(0)
    assert verifyStateProof(source.root, query, changed, limits()).error ==
        StateProofError.InvalidProof
  assert verifyStateProof(source.root, key(128), proof, limits()).error ==
      StateProofError.InvalidProof
  var rightProof = path(source, key(128))
  var rightBranch = array[64, byte](rightProof.nodes[0])
  rightBranch[32] = rightBranch[32] xor 128
  rightProof.nodes[0] = EncodedStateNode(rightBranch)
  let changedRoot = StateRoot(array[32, byte](hashStateNode(rightProof.nodes[0]).value))
  assert verifyStateProof(changedRoot, key(128), rightProof, limits()).error ==
      StateProofError.InvalidProof
  var changed = proof
  changed.value[0] = 1
  assert verifyStateProof(source.root, query, changed, limits()).error ==
      StateProofError.ValueMismatch
  changed = proof
  changed.value.setLen(32)
  assert verifyStateProof(source.root, query, changed, limits()).error ==
      StateProofError.ValueMismatch
  changed = proof
  changed.nodes.setLen(1)
  assert verifyStateProof(source.root, query, changed, limits()).error ==
      StateProofError.IncompleteProof
  assert verifyStateProof(source.root, query, StateProof(), limits()).error ==
      StateProofError.IncompleteProof
  changed = proof
  changed.nodes.add(proof.nodes[1])
  assert verifyStateProof(source.root, query, changed, limits()).error ==
      StateProofError.InvalidProof
  var wrong = array[32, byte](source.root)
  wrong[0] = wrong[0] xor 128 # Root comparison must not discard the left-edge high bit.
  assert verifyStateProof(StateRoot(wrong), query, proof, limits()).error ==
      StateProofError.InvalidProof
  let absentProof = path(source, key(255))
  changed = absentProof
  changed.value = @[1'u8]
  assert verifyStateProof(source.root, key(255), changed, limits()).error ==
      StateProofError.InvalidProof
  var policy = limits()
  policy.nodes = ElementLimit(1)
  reset(1)
  assert verifyStateProof(source.root, query, proof, policy).error == StateProofError.LimitExceeded
  assert calls() == 0
  policy = limits()
  policy.valueBytes = ByteLimit(32)
  assert verifyStateProof(source.root, query, proof, policy).error == StateProofError.LimitExceeded
  assert calls() == 0
  reset(1)
  assert verifyStateProof(source.root, query, proof, limits()).error ==
      StateProofError.BackendFailure
  assert calls() == 1
  for successful in 0..proof.nodes.len:
    refuseAfter(cint(successful))
    assert verifyStateProof(source.root, query, proof, limits()).error ==
        StateProofError.BackendFailure
    assert calls() == cint(successful+1) # The last attempt hashes the long raw value, after all node links match.
  reset(0)
  assert verifyStateProof(source.root, query, proof, limits()).error == StateProofError.None
proc depthAndCanonical() =
  ## The last serialized key bit permits 248 branches plus one leaf, never another bit access.
  var last = default(array[31, byte])
  last[30] = 1
  let source = fixture([StateEntry(key: default(StateKey)), StateEntry(key: StateKey(last),
      value: @[7'u8])])
  let proof = path(source, default(StateKey))
  assert proof.nodes.len == 249
  check(source, default(StateKey), true, @[])
  check(source, StateKey(last), true, @[7'u8])
  check(source, key(128), false, @[]) # A selected zero child terminates after the root node.
  var extra = path(source, key(128))
  assert extra.nodes.len == 1
  extra.nodes.add(proof.nodes[248])
  assert verifyStateProof(source.root, key(128), extra, limits()).error ==
      StateProofError.InvalidProof
  extra = proof
  extra.nodes.add(proof.nodes[248])
  reset(1)
  assert verifyStateProof(source.root, default(StateKey), extra, limits()).error ==
      StateProofError.LimitExceeded
  assert calls() == 0
  reset(0)
  let canonical = encodeStateLeaf(key(0), @[], ByteLimit(0))
  assert canonical.error == StateLayoutError.None, "empty canonical leaf preparation"
  var raw = array[64, byte](canonical.value)
  raw[63] = 1 # Nonzero inline padding is rejected independently of the expected root.
  reset(0)
  let malformed = EncodedStateNode(raw)
  let hashed = hashStateNode(canonical.value)
  assert hashed.error == StateLayoutError.None, "canonical fixture root hashing"
  let malformedRoot = StateRoot(array[32, byte](hashed.value))
  reset(1)
  assert verifyStateProof(malformedRoot, key(0), StateProof(nodes: @[malformed]), limits()).error ==
      StateProofError.InvalidProof
  assert calls() == 0
  let emptyExtra = verifyStateProof(default(StateRoot), key(0), StateProof(nodes: @[malformed]),
      limits())
  assert emptyExtra.error == StateProofError.InvalidProof
  assert calls() == 0
  reset(0)
  let wrongLeaf = encodeStateLeaf(key(128), @[], ByteLimit(0)).value
  let wrongChild = hashStateNode(wrongLeaf).value
  let wrongBranch = encodeStateBranch(wrongChild, default(StateNodeHash))
  let wrongRoot = StateRoot(array[32, byte](hashStateNode(wrongBranch).value))
  let misplaced = verifyStateProof(wrongRoot, key(0),
    StateProof(nodes: @[wrongBranch, wrongLeaf]), limits())
  assert misplaced.error == StateProofError.InvalidProof
  var branches = newSeq[EncodedStateNode](249)
  var child = wrongChild
  for offset in 0..<249:
    let index = 248-offset
    branches[index] = encodeStateBranch(child, default(StateNodeHash))
    child = hashStateNode(branches[index]).value
  let tooDeep = StateRoot(array[32, byte](child))
  assert verifyStateProof(tooDeep, key(0), StateProof(nodes: branches), limits()).error ==
      StateProofError.InvalidProof
mappings()
hostile()
depthAndCanonical()
let source = fixture([StateEntry(key: key(0), value: newSeq[byte](33))])
check(source, key(0), true, newSeq[byte](33))
let before = getOccupiedMem()
for cycle in 0..<1000:
  check(source, key(0), true, newSeq[byte](33))
  check(source, key(1), false, @[])
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_state_proof", 1000, before, after)
echo "PASS storage state proofs: root-bound presence/absence, bounded paths, tampering and retained ownership"
