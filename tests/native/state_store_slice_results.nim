# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime-selected invalid slice results cannot expose an owned byte payload.

import std/cmdline
import ../../src/state/store
import ../../src/codec/[bounded, state_trie, state_layout]
let state = newStateStore([StateEntry(key: default(StateKey), value: @[1'u8])],
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(1),
    totalValueBytes: ByteLimit(1), nodes: TrieNodeLimit(1000)))).value
var outcome = state.snapshot.value.lookup(default(StateKey)).value.copySlice(2, 0, ByteLimit(0))
if paramStr(1) == "owner":
  outcome = default(StateValue).copySlice(0, 0, ByteLimit(
      0)) # Dynamic default-owner path reaches the same selected-success guard.
discard outcome.value
