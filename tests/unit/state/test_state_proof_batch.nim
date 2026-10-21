# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic ordered batch verification retains independent root/key authority and whole-batch quotas.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/[bounded, state_layout, state_trie]
proc main() =
  ## Duplicates remain explicit and all failures discard earlier successful lookups.
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(10))
  let aggregate = StateProofBatchLimits(items: ElementLimit(3), nodes: ElementLimit(3),
      valueBytes: ByteLimit(3))
  let key = chapterKey(StateChapter(1))
  let other = chapterKey(StateChapter(2))
  let leaf = encodeStateLeaf(key, [byte 7], ByteLimit(1)).value
  let root = StateRoot(array[32, byte](hashStateNode(leaf).value))
  let membership = captureStateProof([leaf], [byte 7], limits).value
  let absence = captureStateProof([leaf], [], limits).value
  let queries = @[StateProofQuery(key: key, proof: membership),
    StateProofQuery(key: other, proof: absence), StateProofQuery(key: key, proof: membership)]
  let batch = verifyStateProofs(queries, root, limits, aggregate).value
  assert batch.valid and batch.len == 3
  assert batch.lookupAt(0).value.present and not batch.lookupAt(1).value.present
  assert batch.lookupAt(2).value.bytes == @[byte 7]
  assert batch.lookupAt(3).error == StateProofError.InvalidIndex
  assert default(VerifiedStateProofBatch).lookupAt(0).error == StateProofError.Uninitialized
  assert verifyStateProofs([], root, limits, aggregate).value.valid
  var short = aggregate
  short.nodes = ElementLimit(2)
  assert verifyStateProofs(queries, root, limits, short).error == StateProofError.LimitExceeded
  short = aggregate
  short.valueBytes = ByteLimit(1)
  assert verifyStateProofs(queries, root, limits, short).error == StateProofError.LimitExceeded
  var bad = queries
  bad[2].proof = captureStateProof([leaf], [byte 8], limits).value
  assert verifyStateProofs(bad, root, limits, aggregate).error == StateProofError.MissingValue
  assert batch.lookupAt(2).value.bytes == @[byte 7]
  echo "state-proof-batch: ok"
main()
