# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateInventory", "early": ["auditPreimageLinkage(", "[1] expected: StateInventory but got: StateStoreSnapshot"]}

## Raw mappings cannot grant exhaustive logical request association authority.
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/state/store as state_store
discard auditPreimageLinkage(default(StateStoreSnapshot), PreimageLinkageLimits())
