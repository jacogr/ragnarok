# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic checked extraction probes for default and actual history failures.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../support/history_transition_fixture
import ../../src/state/[history, store]
import ../../src/codec/state/trie as state_trie

case paramStr(1)
of "root":
  # Empty output with a zero-byte budget is a real policy failure, not a successful zero root.
  let outcome = if paramStr(2) == "default": default(HistoryTransitionResult[
      AccumulationRoot]) else:
      accumulationRoot([], default(OutputLogConfig))
  assert outcome.error == (if paramStr(2) == "default": HistoryTransitionError.Uninitialized else: HistoryTransitionError.LimitExceeded)
  echo array[32, byte](outcome.value)[0]
of "entry":
  # Default owners cannot produce history bytes; default results also carry no payload.
  let outcome = if paramStr(2) == "default": default(HistoryTransitionResult[StateEntry]) else:
      advanceHistory(default(HistorySnapshot), default(HistoryAdvance), [], historyConfig())
  assert outcome.error == (if paramStr(2) == "default": HistoryTransitionError.Uninitialized else: HistoryTransitionError.InvalidState)
  echo outcome.value.value.len
of "state":
  # An initialized empty map is not an explicitly stored empty C(3) component.
  let made = newStateStore([], default(StateStoreLimits))
  assert made.error == StateStoreError.None
  var state = made.value
  let outcome = if paramStr(2) == "default": default(HistoryTransitionResult[
      StateStoreSnapshot]) else:
      advanceHistoryState(state, default(HistoryAdvance), [], historyConfig())
  assert outcome.error == (if paramStr(2) == "default": HistoryTransitionError.Uninitialized else: HistoryTransitionError.MissingState)
  echo outcome.value.commitment.entries
else:
  quit(2) # Unknown selectors are harness errors, never valid contract failures.
