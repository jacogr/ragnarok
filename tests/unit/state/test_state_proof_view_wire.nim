# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local partial-view transport preserves sorted keys, raw witnesses and explicit external root authority.
import std/[assertions, syncio]
import ../../../src/state/[trie_proof, proof_view]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc main() =
  ## Exact outer/inner quotas and detached output remain separate from verified root trust.
  let key = chapterKey(StateChapter(1))
  let other = chapterKey(StateChapter(2))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(2))
  let aggregate = StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(2),
      valueBytes: ByteLimit(1))
  let budget = ProofViewLimits(items: ElementLimit(2), valueBytes: ByteLimit(1))
  let leaf = encodeStateLeaf(key, [byte 7], ByteLimit(1)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let present = captureStateProof([leaf], [byte 7], limits).value
  let absent = captureStateProof([leaf], [], limits).value
  let batch = verifyStateProofs([StateProofQuery(key: key, proof: present),
    StateProofQuery(key: other, proof: absent)], root, limits, aggregate).value
  let view = captureProofView(batch, root, budget).value
  var wire = encodeProofView(view, budget, limits, ByteLimit(227)).value
  assert wire.len == 227 and wire[0] == byte('R') and wire[3] == byte('1')
  assert wire[4] == 2 and wire[8] == 1 and wire[39] == 75 and wire[43] == byte('R')
  wire[0] = 0
  assert encodeProofView(view, budget, limits, ByteLimit(227)).value[0] == byte('R')
  assert encodeProofView(view, budget, limits, ByteLimit(226)).error == ProofViewError.LimitExceeded
  let refused = encodeProofView(view, budget, StateProofLimits(), ByteLimit(227))
  assert refused.error == ProofViewError.ProofFailure and refused.proofError ==
      StateProofError.LimitExceeded
  let empty = captureProofView(verifyStateProofs([], root, limits, aggregate).value, root, budget).value
  assert encodeProofView(empty, budget, limits, ByteLimit(8)).value.len == 8
  assert encodeProofView(default(ProofView), budget, limits, ByteLimit(227)).error ==
      ProofViewError.Uninitialized
  echo "state-proof-view-wire: ok"
main()
