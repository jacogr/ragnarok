# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Complete selected logical/source authority and tagged payloads remain private.
import ../../../src/state/parent/logical as parent_logical
var owner = default(ParentLogicalResult[SelectedLogicalParent])
discard owner.status
