# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Partial views retain verified facts under one root without pretending unknown keys are absent.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/state/proof/view as proof_view
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
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
  let one = captureProofView(verifyStateProofs([StateProofQuery(key: key, proof: present)],
    root, limits, aggregate).value, root, budget).value
  let two = captureProofView(verifyStateProofs([StateProofQuery(key: other, proof: absent)],
    root, limits, aggregate).value, root, budget).value
  let united = mergeProofViews(one, two, budget).value
  assert united.len == 2 and united.lookup(key).value.bytes == @[byte 7]
  assert not united.lookup(other).value.present
  assert mergeProofViews(view, view, budget).value.len == 2
  assert mergeProofViews(one, noEvidence, budget).value.len == 1
  assert mergeProofViews(one, two, ProofViewLimits(items: ElementLimit(1),
    valueBytes: ByteLimit(1))).error == ProofViewError.LimitExceeded
  let foreign = captureProofView(verifyStateProofs([], default(StateRoot), limits,
    aggregate).value, default(StateRoot), budget).value
  assert mergeProofViews(view, foreign, budget).error == ProofViewError.WrongRoot
  assert one.len == 1 and two.len == 1 and view.len == 2
  let projected = projectProofView(view, [other], budget).value
  assert projected.len == 1 and not projected.lookup(other).value.present
  assert projected.lookup(key).error == ProofViewError.MissingWitness
  assert projectProofView(view, [], ProofViewLimits()).value.valid
  assert projectProofView(view, [key, key], ProofViewLimits(items: ElementLimit(2),
    valueBytes: ByteLimit(2))).error == ProofViewError.DuplicateKey
  assert projectProofView(view, [chapterKey(StateChapter(3))], budget).error ==
      ProofViewError.MissingWitness
  assert projectProofView(view, [key], ProofViewLimits(items: ElementLimit(1))).error ==
      ProofViewError.LimitExceeded
  assert view.lookup(key).value.bytes == @[byte 7]
  var exported = exportProofQueries(view, budget).value
  assert exported.len == 2
  assert verifyStateProofs(exported, root, limits, aggregate).value.len == 2
  exported[0].key = chapterKey(StateChapter(3))
  assert view.lookup(key).value.bytes == @[byte 7]
  assert exportProofQueries(view, ProofViewLimits()).error == ProofViewError.LimitExceeded
  assert default(StateProof).suppliedByteLength.error == StateProofError.Uninitialized
  assert present.suppliedByteLength.value == 1
  echo "state-proof-view: ok"
main()
