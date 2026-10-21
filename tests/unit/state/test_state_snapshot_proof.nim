# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot proof generation must preserve source roots, policies and retained historical ownership.
import std/[assertions, syncio]
import ../../../src/state/[store, trie_proof, snapshot_proof]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc main() =
  ## Present-empty and absence remain distinct through the complete snapshot adapter.
  let mapLimits = StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(40),
    totalValueBytes: ByteLimit(160), nodes: TrieNodeLimit(1000))
  let policy = StateStoreLimits(trie: mapLimits, writes: ElementLimit(4),
      writeValueBytes: ByteLimit(160))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(40))
  let key = chapterKey(StateChapter(1))
  let original = newStateStore([StateEntry(key: key, value: @[])], policy).value.snapshot.value
  let proof = generateStateProof(original, key, mapLimits, limits).value
  let checked = verifyStateProof(proof, original.commitment.root, key, limits).value
  assert checked.present and checked.bytes.len == 0
  let missing = chapterKey(StateChapter(2))
  assert not verifyStateProof(generateStateProof(original, missing, mapLimits, limits).value,
    original.commitment.root, missing, limits).value.present
  assert generateStateProof(default(StateStoreSnapshot), key, mapLimits, limits).error ==
      StateProofError.Uninitialized
  var short = mapLimits
  short.items = ElementLimit(0)
  assert generateStateProof(original, key, short, limits).error == StateProofError.LimitExceeded
  assert sameStateSnapshot(original, original)
  echo "state-snapshot-proof: ok"
main()
