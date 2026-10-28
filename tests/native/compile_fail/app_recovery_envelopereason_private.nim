# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "envelopeReason"}

## Nested failure reasons cannot be forged into a successful canonical owner.
import ../../../src/app/checkpoint_recovery as app_checkpoint_recovery
let outcome = default(ApplicationRecoveryResult)
discard outcome.envelopeReason
