# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## External callers must not forge or bypass guarded authenticated-read alternatives.
import ../../../src/state/[proof_global, proof_plan, proof_view]
let private = default(GlobalProofResult[StateProofPlan])
discard private.completed
