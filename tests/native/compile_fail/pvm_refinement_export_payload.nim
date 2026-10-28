# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to immutable export owner/result storage.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/pvm/refinement_exports as pvm_refinement_exports
var owner: RefinementExportResult
discard owner.completed
