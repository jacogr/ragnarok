# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "partitionReason"}

## Source-bound plan result alternatives stay private.
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
let refused = planCurrentAccumulationContinuation(default(CurrentAccumulationSequence), default(
    CurrentContinuationLimits))
discard refused.partitionReason
