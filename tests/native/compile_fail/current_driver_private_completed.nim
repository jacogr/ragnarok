# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refused driver storage and inactive parents remain private.
import ../../../src/state/[accumulation_current_driver, accumulation_current_sequence]
let refused = finishCurrentAccumulationSequence(default(PreparedCurrentContinuation))
discard refused.completed
