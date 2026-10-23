# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "initialized"}

## Frozen review source, policies and successful admission alternatives cannot be replaced externally.
import ../../../src/state/current_review
let source = default(CurrentReviewPlan)
discard source.initialized
