# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "inventoryReason"}

## Planned restoration discriminators and payloads remain private.
import ../../../src/state/planned_review_checkpoint as state_planned_review_checkpoint
var value = default(PlannedReviewCheckpointResult)
discard value.inventoryReason
