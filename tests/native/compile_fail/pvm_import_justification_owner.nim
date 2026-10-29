# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private verified-leaf storage and forged result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import "../../../src/state/import/justification" as import_justification
var owner: VerifiedImport
discard owner.data
