# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structural proof capture protects canonical framing, independent ceilings and immutable ownership.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/[bounded, state_layout, state_trie]

proc main() =
  ## Captures are unverified witnesses, including a valid explicit empty path.
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(100))
  let key = chapterKey(StateChapter(1))
  let leaf = encodeStateLeaf(key, [byte 7], ByteLimit(1)).value
  var source = @[leaf]
  var supplied = @[byte 7]
  let proof = captureStateProof(source, supplied, limits).value
  source[0] = default(EncodedStateNode)
  supplied[0] = 8
  assert proof.valid and proof.len == 1
  assert array[64, byte](proof.nodeAt(0).value) == array[64, byte](leaf)
  var bytes = proof.suppliedValue.value
  bytes[0] = 9
  assert proof.suppliedValue.value[0] == 7
  assert proof.nodeAt(-1).error == StateProofError.InvalidIndex
  assert proof.nodeAt(1).error == StateProofError.InvalidIndex
  assert default(StateProof).nodeAt(0).error == StateProofError.Uninitialized
  assert not default(StateProof).valid
  assert captureStateProof([], [], limits).value.valid
  assert captureStateProof([leaf, leaf], [], limits).error == StateProofError.InvalidProof
  assert captureStateProof([default(EncodedStateNode)], [], limits).error ==
      StateProofError.InvalidProof
  var bad = array[64, byte](leaf)
  bad[63] = 1
  assert captureStateProof([EncodedStateNode(bad)], [], limits).error ==
      StateProofError.InvalidProof
  assert captureStateProof([leaf], [], StateProofLimits()).error == StateProofError.LimitExceeded
  assert captureStateProof([], supplied, StateProofLimits()).error == StateProofError.LimitExceeded
  assert captureStateProof(newSeq[EncodedStateNode](250), [], limits).error ==
      StateProofError.LimitExceeded
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let verified = verifyStateProof(proof, root, key, limits)
  assert verified.error == StateProofError.None and verified.value.present
  assert verified.value.bytes == @[byte 7]
  assert array[32, byte](verified.value.root) == array[32, byte](root)
  assert array[31, byte](verified.value.key) == array[31, byte](key)
  assert not default(VerifiedStateLookup).valid
  assert verifyStateProof(proof, default(StateRoot), key, limits).error ==
      StateProofError.RootMismatch
  assert verifyStateProof(proof, root, chapterKey(StateChapter(2)), limits).error ==
      StateProofError.KeyMismatch
  assert verifyStateProof(captureStateProof([leaf], [byte 8], limits).value, root, key,
      limits).error == StateProofError.MissingValue
  for size in [0, 32, 33, 100]:
    # Inline and hashed leaves authenticate exact supplied bytes, including present-empty.
    let payload = newSeq[byte](size)
    let terminal = encodeStateLeaf(key, payload, ByteLimit(100)).value
    let witness = captureStateProof([terminal], payload, limits).value
    let identity = StateRoot(array[32, byte](hashStateNode(terminal).value))
    assert verifyStateProof(witness, identity, key, limits).value.bytes == payload
  let sibling = StateNodeHash(default(array[32, byte]))
  let branch = encodeStateBranch(hashStateNode(leaf).value, sibling)
  let branched = captureStateProof([branch, leaf], [byte 7], limits).value
  let branchRoot = StateRoot(array[32, byte](hashStateNode(branch).value))
  assert verifyStateProof(branched, branchRoot, key, limits).error == StateProofError.None
  let empty = captureStateProof([], [], limits).value
  assert not verifyStateProof(empty, default(StateRoot), key, limits).value.present
  assert verifyStateProof(empty, root, key, limits).error == StateProofError.RootMismatch
  let edge = captureStateProof([branch], [], limits).value
  assert not verifyStateProof(edge, branchRoot, chapterKey(StateChapter(128)), limits).value.present
  assert verifyStateProof(edge, branchRoot, key, limits).error == StateProofError.InvalidProof
  assert verifyStateProof(captureStateProof([branch], [byte 0], limits).value,
    branchRoot, chapterKey(StateChapter(128)), limits).error == StateProofError.InvalidProof
  assert verifyStateProof(default(StateProof), default(StateRoot), key, limits).error ==
      StateProofError.Uninitialized
  echo "state-proof: ok"
main()
