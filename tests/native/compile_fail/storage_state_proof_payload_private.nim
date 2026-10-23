# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Proof results and immutable lookup storage expose only guarded accessors.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/storage/state_proof
let hidden = default(StateProofResult[VerifiedStateLookup])
discard hidden.completed
