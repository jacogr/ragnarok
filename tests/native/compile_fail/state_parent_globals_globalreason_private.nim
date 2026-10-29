# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "globalReason"}

## Original selection/global evidence and tagged alternatives remain private.
import ../../../src/state/parent/globals as parent_globals
var owner = default(ParentGlobalsResult[SelectedParentGlobals])
discard owner.globalReason
