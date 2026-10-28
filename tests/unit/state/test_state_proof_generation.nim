# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generated complete-map paths must reproduce the unchanged independent root calculator.
import std/assertions
import std/syncio
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc main() =
  ## Exercise both leaf encodings, empty edges, conflicting leaves and complete-map quotas.
  let maps = StateTrieLimits(items: ElementLimit(8), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(800), nodes: TrieNodeLimit(2000))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(100))
  var entries: seq[StateEntry] = @[]
  for chapter in [1, 2, 128, 255]:
    # Deliberately choose both root branches and long common prefixes.
    entries.add(StateEntry(key: chapterKey(StateChapter(chapter)), value: newSeq[byte](
        chapter mod 34)))
  let root = stateTrieRoot(entries, maps).value.root
  for chapter in [0, 1, 2, 3, 127, 128, 254, 255]:
    let query = chapterKey(StateChapter(chapter))
    let proof = generateStateProof(entries, query, maps, limits)
    assert proof.error == StateProofError.None
    let checked = verifyStateProof(proof.value, root, query, limits)
    assert checked.error == StateProofError.None
    assert checked.value.present == (chapter in [1, 2, 128, 255])
  assert generateStateProof([], entries[0].key, maps, limits).value.len == 0
  assert generateStateProof([entries[0], entries[0]], entries[0].key, maps, limits).error ==
      StateProofError.DuplicateKey
  var short = maps
  short.nodes = TrieNodeLimit(1)
  assert generateStateProof(entries, entries[0].key, short, limits).error ==
      StateProofError.LimitExceeded
  assert generateStateProof(entries, entries[0].key, maps, StateProofLimits()).error ==
      StateProofError.LimitExceeded
  let retained = generateStateProof(entries, entries[0].key, maps, limits).value
  entries[0].value[0] = 9
  assert verifyStateProof(retained, root, entries[0].key, limits).value.bytes == @[byte 0]
  echo "state-proof-generation: ok"
main()
