# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate typed results, requested identities or verified failure alternatives.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/state/proof/service as proof_service
let plan = default(ServiceProofPlan)
discard plan.data
