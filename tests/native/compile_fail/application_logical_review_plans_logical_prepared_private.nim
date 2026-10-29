# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "prepared"}

## Frozen review source, policies and successful admission alternatives cannot be replaced externally.
import ../../../src/app/logical/review as logical_review
let source = default(LogicalReviewPlan)
discard source.prepared
