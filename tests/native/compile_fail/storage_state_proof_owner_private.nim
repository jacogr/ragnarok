# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Proof results and immutable lookup storage expose only guarded accessors.
# @@Verification={"group": "privacy", "expected": "owner"}
import ../../../src/storage/state_proof as storage_state_proof
let hidden = default(VerifiedStateLookup)
discard hidden.owner
