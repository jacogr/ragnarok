# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "SelectedParentProfile", "early": ["qualifyParentGlobals(", "[1] expected: SelectedParentProfile but got: StateStoreSnapshot"]}

## Detached maps cannot replace selected full-view/profile ownership.
import ../../../src/state/parent_globals as state_parent_globals
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/store as state_store
discard qualifyParentGlobals(default(StateStoreSnapshot), GlobalStateLimits())
