# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "profile"}

## Original selection/global evidence and tagged alternatives remain private.
import ../../../src/state/parent_globals as state_parent_globals
var owner = default(SelectedParentGlobals)
discard owner.profile
