# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Partial verified evidence cannot become a complete-map state snapshot for transitions.
# @@Verification={"group": "nominal", "expected": "StateStoreSnapshot", "early": ["forkStateStore(", "[1] expected: StateStoreSnapshot but got: ProofView"]}
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/store as state_store
let partial = default(ProofView)
discard forkStateStore(partial)
