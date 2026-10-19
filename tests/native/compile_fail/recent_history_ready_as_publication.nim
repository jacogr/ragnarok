# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedRecentHistory", "early": ["publishRecentHistory(", "[1] expected: PreparedRecentHistory but got: PublishedReadyReconciliation"]}

## A post-ready successor cannot replace source-derived recent-history preparation.

import ../../../src/state/[recent_history, ready_reconciliation]
var source: PublishedReadyReconciliation
discard publishRecentHistory(source)
