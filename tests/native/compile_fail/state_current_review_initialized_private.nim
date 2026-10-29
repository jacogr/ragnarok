# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "initialized"}

## Current review owners and result alternatives remain private.
import ../../../src/state/current/review as current_review
var source = default(ReviewedCurrentState)
discard source.initialized
