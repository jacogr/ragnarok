# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private verified-leaf storage and forged result selection.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/import_justification as state_import_justification
var outcome: ImportJustificationResult[int]
discard outcome.completed
