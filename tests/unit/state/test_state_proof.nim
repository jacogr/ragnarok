# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structural proof capture protects canonical framing, independent ceilings and immutable ownership.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/[bounded, state_layout]

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
  echo "state-proof: ok"
main()
