# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored complete maps establish independent roots before partial query verification.
import std/assertions
import ../../src/state/[proof_view, trie_proof]
import ../../src/codec/[bounded, state_layout, state_trie]
const
  mapLimits* = StateTrieLimits(items: ElementLimit(16), perValue: ByteLimit(4096),
    totalValueBytes: ByteLimit(16384), nodes: TrieNodeLimit(31))
  proofLimits* = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4096))
  batchLimits* = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(3984),
    valueBytes: ByteLimit(16384))
  viewLimits* = ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(16384))
proc serviceView*(entries: seq[StateEntry], keys: openArray[StateKey]): ProofView =
  ## Root computation and each path generator must independently agree before a typed read.
  let root = stateTrieRoot(entries, mapLimits).value.root
  var queries: seq[StateProofQuery] = @[]
  for key in keys:
    # Bounded authored test queries retain the actual generated immutable witnesses.
    queries.add(StateProofQuery(key: key,
      proof: generateStateProof(entries, key, mapLimits, proofLimits).value))
  let verified = verifyStateProofs(queries, root, proofLimits, batchLimits)
  assert verified.error == StateProofError.None
  captureProofView(verified.value, root, viewLimits).value
