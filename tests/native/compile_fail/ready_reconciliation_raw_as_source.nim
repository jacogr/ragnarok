# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PublishedAccumulation", "early": ["prepareReadyReconciliation(", "[1] expected: PublishedAccumulation but got: ReadyReconciliationProjection"]}

## Raw queue projections cannot replace the exact coordinated accumulation successor.

import ../../../src/state/ready_reconciliation
var source: ReadyReconciliationProjection
var config: ReadyReconciliationConfig
discard prepareReadyReconciliation(source, config)
