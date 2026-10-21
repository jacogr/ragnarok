# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Recovery results cannot be forged or extracted through private fields.
import ../../../src/app/checkpoint_recovery
let outcome = default(ApplicationRecoveryResult)
discard outcome.status
