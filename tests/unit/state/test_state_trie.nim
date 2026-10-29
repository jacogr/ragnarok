# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplementary runtime contracts for copied roots and guarded failure-only variants.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded

## Exercise public ownership/result contracts independently of the batch oracle's root comparisons.
proc main() =
  let limits = StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(250))
  let absent = default(StateTrieResult[StateTrieCommitment])
  assert absent.error == StateTrieError.Uninitialized
  var entries = @[StateEntry(key: StateKey(default(array[31, byte])), value: @[1'u8, 2, 3])]
  let parsed = stateTrieRoot(entries, limits)
  assert parsed.error == StateTrieError.None
  let saved = array[32, byte](parsed.value.root)
  entries[0].value[0] = 255
  entries.setLen(0)
  assert array[32, byte](parsed.value.root) == saved
  let empty = stateTrieRoot(entries, default(StateTrieLimits))
  assert empty.error == StateTrieError.None
  assert empty.value.nodes == 0 and empty.value.entries == 0
  assert array[32, byte](empty.value.root) == default(array[32, byte])
  entries = @[default(StateEntry), default(StateEntry)]
  let rejected = stateTrieRoot(entries, limits)
  assert rejected.error == StateTrieError.DuplicateKey
  # Failed/default payload reads run in isolated processes in the trial runner.
  let limited = stateTrieRoot(entries, default(StateTrieLimits))
  assert limited.error == StateTrieError.LimitExceeded

  echo "PASS state trie native: copied roots, empty identity, default/failure reasons"

main()
