# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedReadyReconciliation", "early": ["publishReadyReconciliation(", "[1] expected: PreparedReadyReconciliation but got: PublishedAccumulation"]}

## A coordinated accumulation successor cannot replace the source-derived ready preparation.

import ../../../src/state/[ready_reconciliation, accumulation_publication]
var source: PublishedAccumulation
discard publishReadyReconciliation(source)
