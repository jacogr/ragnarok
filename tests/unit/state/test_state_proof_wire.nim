# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local proof serialization is bounded and exact, with root/key trust deliberately supplied separately.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/[bounded, state_layout, state_trie]
proc main() =
  ## Verify exact framing, detached output and both individual and outer byte limits.
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(100))
  let key = chapterKey(StateChapter(1))
  let leaf = encodeStateLeaf(key, [byte 9], ByteLimit(1)).value
  let proof = captureStateProof([leaf], [byte 9], limits).value
  var wire = encodeStateProof(proof, limits, ByteLimit(75)).value
  assert wire.len == 75 and wire[0] == byte('R') and wire[3] == byte('1')
  assert wire[4] == 1 and wire[5] == 0 and wire[6] == 1 and wire[9] == 0
  assert wire[10] == 129 and wire[74] == 9
  wire[74] = 8
  assert encodeStateProof(proof, limits, ByteLimit(75)).value[74] == 9
  assert encodeStateProof(proof, limits, ByteLimit(74)).error == StateProofError.LimitExceeded
  assert encodeStateProof(proof, StateProofLimits(), ByteLimit(75)).error ==
      StateProofError.LimitExceeded
  assert encodeStateProof(default(StateProof), limits, ByteLimit(100)).error ==
      StateProofError.Uninitialized
  let empty = captureStateProof([], [], limits).value
  assert encodeStateProof(empty, limits, ByteLimit(10)).value.len == 10
  echo "state-proof-wire: ok"
main()
