# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "guestReason"}

## Refused later entries retain no public inactive engine result.
import ../../../src/state/accumulation/current/sequence as accumulation_current_sequence
let refused = runCurrentAccumulationContinuation(default(PreparedCurrentContinuation), default(
    CurrentContinuationExecutionLimits))
discard refused.guestReason
