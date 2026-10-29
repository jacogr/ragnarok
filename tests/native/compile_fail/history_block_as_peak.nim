# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recent-block positions cannot silently become MMR belt positions.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "HistoryBlockIndex"}

import ../../../src/codec/state/history as state_history
var owner: HistorySnapshot
var index: HistoryBlockIndex
let peak = historyPeakAt(owner, index)
discard peak
