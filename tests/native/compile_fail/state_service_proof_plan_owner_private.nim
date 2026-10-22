# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "plan"}

## Callers cannot forge a semantic service selector from arbitrary generic requested keys.
import ../../../src/state/proof_service
let private = default(ServiceProofPlan)
discard private.plan
