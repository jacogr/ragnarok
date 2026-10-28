# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local proof serialization is bounded and exact, with root/key trust deliberately supplied separately.
import std/assertions
import std/syncio
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
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
  let encoded = encodeStateProof(proof, limits, ByteLimit(75)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let decoded = decodeStateProof(encoded, limits, ByteLimit(75)).value
  assert verifyStateProof(decoded, root, key, limits).value.bytes == @[byte 9]
  for size in 0..<encoded.len:
    # Every truncated prefix refuses without a partial owner or index access.
    var prefix = newSeq[byte](size)
    for i in 0..<size: prefix[i] = encoded[i]
    assert decodeStateProof(prefix, limits, ByteLimit(100)).error == StateProofError.Truncated
  var bad = encoded
  bad.add(0)
  assert decodeStateProof(bad, limits, ByteLimit(100)).error == StateProofError.NonCanonical
  bad = encoded
  bad[3] = byte('2')
  assert decodeStateProof(bad, limits, ByteLimit(100)).error == StateProofError.NonCanonical
  bad = encoded
  bad[4] = 250
  assert decodeStateProof(bad, limits, ByteLimit(100)).error == StateProofError.LimitExceeded
  bad = encoded
  bad[73] = 1
  assert decodeStateProof(bad, limits, ByteLimit(100)).error == StateProofError.InvalidProof
  assert decodeStateProof(encoded, limits, ByteLimit(74)).error == StateProofError.LimitExceeded
  assert decodeStateProof(encodeStateProof(empty, limits, ByteLimit(10)).value,
    limits, ByteLimit(10)).value.valid
  echo "state-proof-wire: ok"
main()
