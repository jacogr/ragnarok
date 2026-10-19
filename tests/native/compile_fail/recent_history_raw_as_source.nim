# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PublishedReadyReconciliation", "early": ["prepareRecentHistory(", "[1] expected: PublishedReadyReconciliation but got: HistoryAdvance"]}

## Loose header/root projections cannot replace a complete post-ready source.

import ../../../src/state/[recent_history, history]
var source: HistoryAdvance
var config: RecentHistoryConfig
discard prepareRecentHistory(source, config)
