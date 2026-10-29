# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## External callers must not forge or bypass guarded authenticated-read alternatives.
import ../../../src/state/planned/proof as planned_proof
import ../../../src/state/proof/[plan as proof_plan, view as proof_view]
let private = default(PlannedProofResult[ProofView])
discard private.completed
