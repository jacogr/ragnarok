# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot turn an uninitialized result into successful history state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/history as state_history
import ../../../src/codec/state_trie as codec_state_trie
var hidden = default(HistoryTransitionResult[StateEntry])
hidden.status = HistoryTransitionError.None
