# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## External code cannot forge the retained ancestry, discovery or prepared admission certificate.
import ../../../src/state/ancestor_context
let owner = default(AncestorContextResult[int])
discard owner.status
