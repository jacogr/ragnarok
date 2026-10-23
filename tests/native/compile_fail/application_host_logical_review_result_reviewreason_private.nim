# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "reviewReason"}

## Host logical authority and backing storage remain private and cannot be retagged or substituted.
import ../../../src/app/logical_review
let source = default(LogicalReviewResult[int])
discard source.reviewReason
