# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A typed C(11) read keeps missing evidence, authenticated absence and invalid bytes separate.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/state/proof/view as proof_view
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    safrole as state_safrole]
proc view(entries: seq[StateEntry], query: StateKey): ProofView =
  ## Independently commit a complete authored map before preparing and verifying the selected witness.
  let maps = StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(5),
    totalValueBytes: ByteLimit(5), nodes: TrieNodeLimit(1))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(5))
  let root = stateTrieRoot(entries, maps).value.root
  let proof = generateStateProof(entries, query, maps, limits).value
  let batch = verifyStateProofs([StateProofQuery(key: query, proof: proof)], root, limits,
    StateProofBatchLimits(items: ElementLimit(1), nodes: ElementLimit(249), valueBytes: ByteLimit(5))).value
  captureProofView(batch, root, ProofViewLimits(items: ElementLimit(1), valueBytes: ByteLimit(5))).value
proc main() =
  ## Exact E4 is required: the existing prefix decoder cannot make a suffixed value canonical.
  let key = chapterKey(StateChapter(11))
  for time in [0'u32, 1'u32, 4294967295'u32]:
    let source = @[timeEntry(StateTime(time))]
    assert uint32(view(source, key).readProofTime.value) == time
  assert default(ProofView).readProofTime.error == ProofViewError.Uninitialized
  assert view(@[], key).readProofTime.error == ProofViewError.AbsentValue
  assert view(@[], chapterKey(StateChapter(12))).readProofTime.error ==
      ProofViewError.MissingWitness
  for size in [0, 1, 3, 5]:
    # Authenticated malformed state remains malformed, even when the trie proof itself is valid.
    assert view(@[StateEntry(key: key, value: newSeq[byte](size))], key).readProofTime.error ==
        ProofViewError.InvalidValue
  echo "state-proof-view-time: ok"
main()
