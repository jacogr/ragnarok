# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "PreparedCurrentChainUpdate", "early": ["captureCurrentProfile(", "[1] expected: PreparedCurrentChainUpdate but got: StateStoreSnapshot"]}

## Equal-root or detached maps cannot substitute for the original execution owner.
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/store as state_store
discard captureCurrentProfile(default(StateStoreSnapshot), CurrentProfileLimits())
