# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot turn an uninitialized result into successful history state.
import ../../../src/state/history
import ../../../src/codec/state_trie
var hidden = default(HistoryTransitionResult[StateEntry])
hidden.status = HistoryTransitionError.None
