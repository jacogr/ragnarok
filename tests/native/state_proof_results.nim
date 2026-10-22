# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime misuse probes reach actual success-only extraction under checked optimized compilation.
import std/[assertions, cmdline]
import ../../src/state/trie_proof
import ../../src/codec/[bounded, state_layout, state_trie]
proc extract[T](outcome: StateProofResult[T]) =
  ## The same generic public accessor must reject defaults and every actual failure payload type.
  discard outcome.value
proc main() =
  ## Genuine capture, membership, absence and batch controls precede deliberately refused extraction.
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(2))
  let key = chapterKey(StateChapter(1))
  let leaf = encodeStateLeaf(key, [byte 7], ByteLimit(1)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let proof = captureStateProof([leaf], [byte 7], limits).value
  let verified = verifyStateProof(proof, root, key, limits)
  assert verified.error == StateProofError.None and verified.value.bytes == @[byte 7]
  let aggregate = StateProofBatchLimits(items: ElementLimit(1), nodes: ElementLimit(1),
      valueBytes: ByteLimit(1))
  let batch = verifyStateProofs([StateProofQuery(key: key, proof: proof)], root, limits,
      aggregate).value
  assert batch.lookupAt(0).value.present
  case paramStr(1)
  of "default": extract(default(StateProofResult[StateProof])) # No default proof payload.
  of "capture": extract(captureStateProof([leaf], [], StateProofLimits())) # Actual policy refusal.
  of "verify": extract(verifyStateProof(proof, default(StateRoot), key, limits)) # Wrong authority.
  of "index": extract(proof.nodeAt(1)) # Invalid ordinal has no fixed node.
  of "batch": extract(verifyStateProofs([StateProofQuery(key: key, proof: proof)], root, limits,
      StateProofBatchLimits())) # No partial batch.
  of "lookup": extract(batch.lookupAt(1)) # Invalid result ordinal has no lookup.
  of "wire": extract(encodeStateProof(proof, limits, ByteLimit(1))) # No partial bytes.
  of "decode": extract(decodeStateProof([], limits, ByteLimit(1))) # No partial decoded owner.
  else:
    extract(verified) # Positive control uses exactly the same guarded extraction.
main()
