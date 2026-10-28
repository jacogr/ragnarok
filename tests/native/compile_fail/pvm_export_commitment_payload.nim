# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private tree storage or forged result selection.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/export_commitment as state_export_commitment
var outcome: ExportCommitmentResult[int]
discard outcome.completed
