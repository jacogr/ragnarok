# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "HistoryStateRoot", "early": ["correctHistoryParent(", "[2] expected: HistoryStateRoot but got: AccumulationRoot"]}

## An output root cannot correct a parent state root.

import ../../../src/state/history as state_history
import ../../../src/codec/state_history as codec_state_history
var source: HistorySnapshot
var root: AccumulationRoot
var config: HistoryConfig
discard correctHistoryParent(source, root, config)
