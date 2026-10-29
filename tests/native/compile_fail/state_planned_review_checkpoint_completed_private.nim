# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Planned restoration discriminators and payloads remain private.
import ../../../src/state/planned/review_checkpoint as planned_review_checkpoint
var value = default(PlannedReviewCheckpointResult)
discard value.completed
