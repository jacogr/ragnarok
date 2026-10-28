# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateInventory", "early": ["auditPreimageContent(", "[1] expected: StateInventory but got: StateStoreSnapshot"]}

## Raw complete or partial mappings cannot bypass exact inventory provenance.
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/store as state_store
discard auditPreimageContent(default(StateStoreSnapshot), PreimageContentLimits())
