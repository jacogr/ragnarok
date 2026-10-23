# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "ChainView", "early": ["captureParentProfile(", "[1] expected: ChainView but got: StateStoreSnapshot"]}

## A detached map cannot replace original selected history and finality.
import ../../../src/state/[parent_profile, store]
discard captureParentProfile(default(StateStoreSnapshot), ParentProfileLimits())
