# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "manifestReason"}

## Current state owners and result alternatives remain private.
import ../../../src/state/current_state as state_current_state
var source = default(CurrentStateResult[CurrentStateSerialization])
discard source.manifestReason
