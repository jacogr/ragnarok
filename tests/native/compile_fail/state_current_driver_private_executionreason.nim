# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "executionReason"}

## Refused driver storage and inactive parents remain private.
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
let refused = finishCurrentAccumulationSequence(default(PreparedCurrentContinuation))
discard refused.executionReason
