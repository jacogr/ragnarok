# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateStoreSnapshot", "early": ["validateGlobalState(", "[1] expected: StateStoreSnapshot but got: ProofView"]}

## Reject forged serialization authority at the actual public boundary.
import ../../../src/state/global_snapshot
import ../../../src/state/proof_view
import ../../../src/codec/state_composition
discard validateGlobalState(default(ProofView), default(StateProfile), default(GlobalStateLimits))
