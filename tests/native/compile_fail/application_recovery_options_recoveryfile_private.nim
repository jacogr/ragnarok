# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "recoveryFile"}

## Complete recovery configuration cannot be forged or mutated through private parser fields.
import ../../../src/app/options
let candidate = default(Options)
discard candidate.recoveryFile
