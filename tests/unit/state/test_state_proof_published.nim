# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every key in all fourteen unchanged pinned maps supplies membership under its original published root.
import std/[assertions, syncio]
import ../../../src/state/[store, trie_proof, snapshot_proof]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../support/published_state
proc main() {.raises.} =
  ## Reuse exact pinned fixture preparation without converting a partial witness into a complete map.
  let mappings = publishedMappings()
  assert mappings.len == 14
  for mapping in mappings:
    let policy = policy(mapping, mapping)
    let snapshot = newStateStore(mapping.entries, policy).value.snapshot.value
    let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: policy.trie.perValue)
    for entry in mapping.entries:
      # Root expectations come from the pinned map fixture, never the new generator.
      let proof = generateStateProof(snapshot, entry.key, policy.trie, limits).value
      let checked = verifyStateProof(proof, mapping.root, entry.key, limits).value
      assert checked.present and checked.bytes == entry.value
    var missing = default(array[31, byte])
    missing[0] = 254
    let query = StateKey(missing)
    if snapshot.lookup(query).error == StateStoreError.MissingKey:
      # Exact absence is cross-checked against the complete retained map, not a guessed chapter policy.
      let proof = generateStateProof(snapshot, query, policy.trie, limits).value
      assert not verifyStateProof(proof, mapping.root, query, limits).value.present
    matches(snapshot, mapping)
  echo "state-proof-published: ok"
try:
  main()
except:
  quit(2) # Fixture failures cannot count as proof refusals or successful empty replay.
