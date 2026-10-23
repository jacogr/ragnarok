# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Selected parent/source and tagged result storage remain private.
import ../../../src/state/parent_profile
var owner = default(ParentProfileResult[SelectedParentProfile])
discard owner.status
