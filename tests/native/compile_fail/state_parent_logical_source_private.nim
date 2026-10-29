# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "source"}

## Complete selected logical/source authority and tagged payloads remain private.
import ../../../src/state/parent/logical as parent_logical
var owner = default(SelectedLogicalParent)
discard owner.source
