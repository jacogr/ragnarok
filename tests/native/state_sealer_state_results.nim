# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default publication results cannot expose an immutable working-map payload.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/sealer_state as state_sealer_state
import ../../src/state/sealer_schedule as state_sealer_schedule
import ../../src/state/store as state_store
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded

## A real initialized parent deliberately lacks C(4), giving a distinct actual publication refusal.
proc refused(): SealerStateResult =
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(4),
    totalValueBytes: ByteLimit(4), nodes: TrieNodeLimit(10)), writes: ElementLimit(0),
        writeValueBytes: ByteLimit(0))
  let parent = newStateStore(@[timeEntry(StateTime(0))], limits).value.snapshot.value
  var state = default(StateStore)
  selectSafroleScheduleState(state, parent, StateTime(1), default(SealerScheduleConfig))

let outcome = if paramStr(1) == "default": default(SealerStateResult) else:
  refused() # Actual missing-parent-chapter refusal contains no map.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot stand in for guarded access.
assert outcome.error == (if paramStr(1) == "default": SealerScheduleError.Uninitialized else: SealerScheduleError.MissingState)
echo outcome.value.commitment.entries
