# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Query identities and successful alternatives remain private to their immutable owner.
import ../../../src/state/proof_plan as state_proof_plan
let private = default(StateProofPlan)
discard private.data
