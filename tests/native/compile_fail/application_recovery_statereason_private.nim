# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "stateReason"}

## Recovery results cannot be forged or extracted through private fields.
import ../../../src/app/checkpoint/recovery as checkpoint_recovery
let outcome = default(ApplicationRecoveryResult)
discard outcome.stateReason
