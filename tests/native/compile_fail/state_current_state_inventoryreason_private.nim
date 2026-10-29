# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "inventoryReason"}

## Current state owners and result alternatives remain private.
import ../../../src/state/current/state as current_state
var source = default(CurrentStateResult[CurrentStateSerialization])
discard source.inventoryReason
