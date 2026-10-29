# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "preparationReason"}

## Current review owners and result alternatives remain private.
import ../../../src/state/current/review as current_review
var source = default(CurrentReviewResult[ReviewedCurrentState])
discard source.preparationReason
