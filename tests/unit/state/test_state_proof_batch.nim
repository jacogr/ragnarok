# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic ordered batch verification retains independent root/key authority and whole-batch quotas.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
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
  let maps = StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(1),
    totalValueBytes: ByteLimit(1), nodes: TrieNodeLimit(1))
  let source = @[StateEntry(key: key, value: @[byte 7])]
  let generated = generateStateProofs(source, [key, other, key], maps, limits, aggregate).value
  assert generated.valid and generated.len == 3
  assert generated.queryAt(3).error == StateProofError.InvalidIndex
  assert default(StateProofSet).queryAt(0).error == StateProofError.Uninitialized
  for i in 0..<generated.len:
    # Generated set order, duplicate accounting and absence evidence match explicit verification.
    let query = generated.queryAt(i).value
    assert verifyStateProof(query.proof, root, query.key, limits).value.present == (i != 1)
  assert generateStateProofs(source, [key, other, key], maps, limits, short).error ==
      StateProofError.LimitExceeded
  assert generateStateProofs(source, [], maps, limits, aggregate).value.valid
  echo "state-proof-batch: ok"
main()
