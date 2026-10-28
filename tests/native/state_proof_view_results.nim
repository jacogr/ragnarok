# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime partial-view guards preserve missing evidence, failed roots and typed-reader refusal.
import std/assertions
import std/cmdline
import ../../src/state/trie_proof as state_trie_proof
import ../../src/state/proof_view as state_proof_view
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
proc extract[T](outcome: ProofViewResult[T]) =
  ## Default and failed alternatives cannot yield a partial view, lookup, time or byte envelope.
  discard outcome.value
proc main() =
  ## Build genuinely verified presence and absence before choosing any negative extraction path.
  let key = chapterKey(StateChapter(1))
  let other = chapterKey(StateChapter(2))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1))
  let aggregate = StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(2),
      valueBytes: ByteLimit(2))
  let budget = ProofViewLimits(items: ElementLimit(2), valueBytes: ByteLimit(2))
  let leaf = encodeStateLeaf(key, [byte 7], ByteLimit(1)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let present = captureStateProof([leaf], [byte 7], limits).value
  let absent = captureStateProof([leaf], [], limits).value
  let batch = verifyStateProofs([StateProofQuery(key: key, proof: present),
    StateProofQuery(key: other, proof: absent)], root, limits, aggregate).value
  let view = captureProofView(batch, root, budget).value
  assert view.lookup(key).value.bytes == @[byte 7] and not view.lookup(other).value.present
  let foreign = captureProofView(verifyStateProofs([], default(StateRoot), limits, aggregate).value,
    default(StateRoot), budget).value
  case paramStr(1)
  of "default": extract(default(ProofViewResult[ProofView])) # No initialized payload.
  of "missing": extract(view.lookup(chapterKey(StateChapter(3)))) # Unknown differs from absence.
  of "capture": extract(captureProofView(batch, default(StateRoot), budget)) # Foreign root has no prefix.
  of "merge": extract(mergeProofViews(view, foreign, budget)) # No root switching through union.
  of "project": extract(projectProofView(view, [chapterKey(StateChapter(3))], budget)) # No guessed evidence.
  of "wire": extract(encodeProofView(view, budget, limits, ByteLimit(1))) # No partial envelope.
  of "decode": extract(decodeProofView([], root, budget, limits, aggregate, ByteLimit(
      1))) # No partial verified collection.
  of "absent-bytes": discard view.lookup(other).value.bytes # Proven absence cannot disclose the neighboring value.
  of "time": extract(view.readProofTime) # Missing C(11) cannot become a zero timeslot.
  else:
    extract(view.lookup(key)) # Genuine positive control uses the same success-only accessor.
main()
