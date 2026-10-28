# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged private export-erasure authority.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/export_erasure as state_export_erasure
var candidate: ExportErasure
discard candidate.data
