# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "SelectedParentProfile", "early": ["qualifyParentGlobals(", "[1] expected: SelectedParentProfile but got: StateStoreSnapshot"]}

## Detached maps cannot replace selected full-view/profile ownership.
import ../../../src/state/parent/globals as parent_globals
import ../../../src/state/[global_snapshot, store]
discard qualifyParentGlobals(default(StateStoreSnapshot), GlobalStateLimits())
