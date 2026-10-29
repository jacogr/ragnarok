# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "DerivedCurrentProfile", "early": ["qualifyCurrentGlobals(", "[1] expected: DerivedCurrentProfile but got: StateStoreSnapshot"]}

## Detached maps cannot replace source-bound derived current profile ownership.
import ../../../src/state/current/globals as current_globals
import ../../../src/state/[global_snapshot, store]
discard qualifyCurrentGlobals(default(StateStoreSnapshot), GlobalStateLimits())
