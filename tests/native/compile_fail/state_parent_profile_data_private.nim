# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Selected parent/source and tagged result storage remain private.
import ../../../src/state/parent/profile as parent_profile
var owner = default(SelectedParentProfile)
discard owner.data
