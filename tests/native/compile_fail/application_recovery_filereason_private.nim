# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "fileReason"}

## File refusal cannot be substituted for a successful recovery graph.
import ../../../src/app/checkpoint_recovery
let outcome = default(ApplicationRecoveryResult)
discard outcome.fileReason
