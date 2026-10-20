# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to immutable export owner/result storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/pvm/refinement_exports
var owner: RefinementExports
discard owner.data
