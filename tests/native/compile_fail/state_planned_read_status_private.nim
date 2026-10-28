# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## External callers must not forge or bypass guarded authenticated-read alternatives.
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/proof_view as state_proof_view
let private = default(PlannedProofResult[ProofView])
discard private.status
