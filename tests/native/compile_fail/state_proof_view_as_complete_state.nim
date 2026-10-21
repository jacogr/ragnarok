# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Partial verified evidence cannot become a complete-map state snapshot for transitions.
# @@Verification={"group": "nominal", "expected": "StateStoreSnapshot", "early": ["forkStateStore(", "[1] expected: StateStoreSnapshot but got: ProofView"]}
import ../../../src/state/[proof_view, store]
let partial = default(ProofView)
discard forkStateStore(partial)
