# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Proposed history payloads remain private even on default results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/history
import ../../../src/codec/state_trie
let hidden = default(HistoryTransitionResult[StateEntry])
discard hidden.completed
