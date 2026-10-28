# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate partial verified state or nested success/failure payloads.
# @@Verification={"group": "privacy", "expected": "proofReason"}
import ../../../src/state/proof_view as state_proof_view
let owner = default(ProofViewResult[ProofView])
discard owner.proofReason
