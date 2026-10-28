# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic invalid-access probes with valid controls under the same optimized profile.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/storage/full_state_trie as storage_full_state_trie
import ../../src/storage/node_records as storage_node_records
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie

proc main() =
  ## Select dynamic sources so checked preconditions are exercised at runtime.
  let member = paramStr(1)
  let origin = paramStr(2)
  let limits = FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(1),
    perValue: ByteLimit(0), totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(1)))
  let initialized = newFullStateTrie([StateEntry(key: default(StateKey))], limits)
  assert initialized.error == TrieError.None
  let trie = initialized.value
  case member
  of "result":
    let selected = if origin == "default": default(TrieResult[FullStateTrie])
      elif origin == "failed": newFullStateTrie([StateEntry(key: default(StateKey))], default(FullStateTrieLimits))
      else: initialized
    echo selected.value.commitment.entries # Failed/default construction cannot expose a revision.
  of "take":
    var selected = if origin == "default": default(TrieResult[TrieExport])
      elif origin == "failed": exportFullTrie(trie, default(TrieExportLimits))
      else: exportFullTrie(trie, TrieExportLimits(records: TrieNodeLimit(1), valueBytes: ByteLimit(0)))
    var held = default(TrieExport)
    if origin == "moved":
      held = selected.takeValue # The first owned export remains alive when a second extraction is attempted.
      assert held.records.len == 1
    echo selected.takeValue.records.len
  of "apply":
    let selected = if origin == "failed": trie.apply([TrieWrite(key: default(StateKey))])
      else: trie.apply([])
    echo selected.value.commitment.entries # A refused batch exposes no candidate.
  of "lookup":
    var key = default(array[31, byte])
    if origin == "failed": key[0] = 1 # Produce a real missing-key result.
    let selected = trie.lookup(StateKey(key))
    echo selected.value.byteLength
  of "metadata":
    let selected = if origin == "default": default(FullStateTrie) else: trie
    echo selected.commitment.entries # An uninitialized revision is not an empty complete map.
  of "length", "bytes":
    let selected = if origin == "default": default(TrieValue) else: trie.lookup(default(
        StateKey)).value
    if member == "length": echo selected.byteLength # Default retained values have no leaf.
    else: echo selected.bytes.len # Copying must validate its retained owner too.
  else:
    quit(2) # Unknown arguments are harness errors, never successful rejection evidence.

main()
