# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime-selected default block owners and invalid key results cannot expose usable snapshots or keys.

import std/cmdline
import std/syncio
import ../../src/chain/genesis as chain_genesis
import ../../src/state/store as state_store
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded

let selected = paramStr(1)
if selected == "block":
  let absent = default(BlockSnapshot)
  discard absent.stateSnapshot # Checked optimized extraction must reject the default chain owner.
else:
  let empty = newStateStore([], default(StateStoreLimits)).value.snapshot.value
  let source = if selected == "owner": default(StateStoreSnapshot) else: empty
  let rejected = source.keyAt(StateEntryIndex(0))
  discard rejected.value # Both default owners and invalid ranges select reasons alone.
