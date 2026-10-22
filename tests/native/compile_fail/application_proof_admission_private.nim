# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Private state and authority cannot be inspected or forged by consumers.
import ../../../src/app/services
let private = default(StateProofAdmission)
discard private.status
