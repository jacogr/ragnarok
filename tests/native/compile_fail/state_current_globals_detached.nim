# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "DerivedCurrentProfile", "early": ["qualifyCurrentGlobals(", "[1] expected: DerivedCurrentProfile but got: StateStoreSnapshot"]}

## Detached maps cannot replace source-bound derived current profile ownership.
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/store as state_store
discard qualifyCurrentGlobals(default(StateStoreSnapshot), GlobalStateLimits())
