# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private tree storage or forged result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import "../../../src/state/export/commitment" as export_commitment
var owner: ExportCommitment
discard owner.data
