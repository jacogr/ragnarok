# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Partial views retain verified facts under one root without pretending unknown keys are absent.
import std/[assertions, syncio]
import ../../../src/state/[trie_proof, proof_view]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc main() =
  ## Unsorted requests become deterministic exact-key evidence without widening root authority.
  let key = chapterKey(StateChapter(1))
  let other = chapterKey(StateChapter(2))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(2))
  let aggregate = StateProofBatchLimits(items: ElementLimit(3), nodes: ElementLimit(3),
      valueBytes: ByteLimit(3))
  let budget = ProofViewLimits(items: ElementLimit(2), valueBytes: ByteLimit(1))
  let leaf = encodeStateLeaf(key, [byte 7], ByteLimit(1)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let present = captureStateProof([leaf], [byte 7], limits).value
  let absent = captureStateProof([leaf], [], limits).value
  let batch = verifyStateProofs([StateProofQuery(key: other, proof: absent),
    StateProofQuery(key: key, proof: present)], root, limits, aggregate).value
  let view = captureProofView(batch, root, budget).value
  assert view.valid and view.len == 2
  assert view.lookupAt(0).value.present and not view.lookupAt(1).value.present
  assert view.lookupAt(0).value.bytes == @[byte 7]
  assert array[32, byte](view.root) == array[32, byte](root)
  assert view.lookupAt(-1).error == ProofViewError.InvalidIndex
  assert default(ProofView).lookupAt(0).error == ProofViewError.Uninitialized
  assert captureProofView(default(VerifiedStateProofBatch), root, budget).error ==
      ProofViewError.Uninitialized
  assert captureProofView(batch, default(StateRoot), budget).error == ProofViewError.WrongRoot
  assert captureProofView(batch, root, ProofViewLimits()).error == ProofViewError.LimitExceeded
  let duplicated = verifyStateProofs([StateProofQuery(key: key, proof: present),
    StateProofQuery(key: key, proof: present)], root, limits, aggregate).value
  assert captureProofView(duplicated, root, ProofViewLimits(items: ElementLimit(2),
    valueBytes: ByteLimit(2))).error == ProofViewError.DuplicateKey
  let empty = verifyStateProofs([], root, limits, aggregate).value
  assert captureProofView(empty, root, ProofViewLimits()).value.valid
  assert view.lookup(key).value.present and view.lookup(key).value.bytes == @[byte 7]
  assert not view.lookup(other).value.present
  assert view.lookup(chapterKey(StateChapter(3))).error == ProofViewError.MissingWitness
  assert default(ProofView).lookup(key).error == ProofViewError.Uninitialized
  let noEvidence = captureProofView(empty, root, ProofViewLimits()).value
  assert noEvidence.lookup(key).error == ProofViewError.MissingWitness
  echo "state-proof-view: ok"
main()
