# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## External callers must not forge or bypass guarded authenticated-read alternatives.
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/proof_view as state_proof_view
let private = default(GlobalProofResult[StateProofPlan])
discard private.completed
