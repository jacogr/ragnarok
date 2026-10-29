# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refused driver storage and inactive parents remain private.
import ../../../src/state/accumulation/current/[driver as accumulation_current_driver,
    sequence as accumulation_current_sequence]
let refused = finishCurrentAccumulationSequence(default(PreparedCurrentContinuation))
discard refused.status
