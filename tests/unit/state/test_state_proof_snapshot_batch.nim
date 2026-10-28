# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot batches copy one bounded full map and preserve ordered present/absent queries.
import std/assertions
import std/syncio
import ../../support/state_proof_service_helpers
import ../../../src/state/store as state_store
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/snapshot_proof as state_snapshot_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc main() =
  ## A repeated query stays repeated in raw batch APIs; typed query plans impose uniqueness separately.
  let key = chapterKey(StateChapter(11))
  let missing = chapterKey(StateChapter(12))
  let store = newStateStore([StateEntry(key: key, value: @[byte 4])], StateStoreLimits(
      trie: mapLimits, writes: ElementLimit(16), writeValueBytes: ByteLimit(16384))).value
  let source = store.snapshot.value
  let queries = [key, missing, key]
  let proofs = generateStateProofs(source, queries, mapLimits, proofLimits, batchLimits).value
  assert proofs.len == 3
  for i in 0..<proofs.len:
    # Every witness authenticates against the retained source commitment, never a derived partial root.
    let query = proofs.queryAt(i).value
    let found = verifyStateProof(query.proof, source.commitment.root, query.key, proofLimits).value
    assert found.present == (i != 1)
    assert array[31, byte](query.key) == array[31, byte](queries[i])
  var short = batchLimits
  short.items = ElementLimit(2)
  assert generateStateProofs(source, queries, mapLimits, proofLimits, short).error ==
      StateProofError.LimitExceeded
  assert generateStateProofs(default(StateStoreSnapshot), queries, mapLimits, proofLimits,
      batchLimits).error == StateProofError.Uninitialized
  assert generateStateProofs(source, [], mapLimits, proofLimits, batchLimits).value.len == 0
  echo "state-proof-snapshot-batch: ok"
main()
