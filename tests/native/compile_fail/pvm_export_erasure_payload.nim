# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged private export-erasure authority.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/export_erasure
var candidate: ExportErasureResult[ExportErasure]
discard candidate.completed
