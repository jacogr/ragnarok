# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A root-free requested-key plan cannot become a complete state map or execution authority.
# @@Verification={"group": "nominal", "expected": "StateStoreSnapshot", "early": ["forkStateStore(", "[1] expected: StateStoreSnapshot but got: ServiceProofPlan"]}
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/store as state_store
let plan = default(ServiceProofPlan)
discard forkStateStore(plan)
