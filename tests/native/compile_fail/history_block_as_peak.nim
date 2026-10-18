# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recent-block positions cannot silently become MMR belt positions.
import ../../../src/codec/state_history
var owner: HistorySnapshot
var index: HistoryBlockIndex
let peak = historyPeakAt(owner, index)
discard peak
