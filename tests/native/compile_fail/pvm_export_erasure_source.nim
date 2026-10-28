# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached trees or substituted full-width row/shard coordinates.

# @@Verification={"group": "nominal", "expected": "BundleErasure", "early": ["prepareExportErasure(", "[1] expected: BundleErasure but got: ExportCommitment"]}

import ../../../src/state/export_erasure as state_export_erasure
import ../../../src/state/export_commitment as state_export_commitment
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/state/erasure_words as state_erasure_words
discard prepareExportErasure(default(ExportCommitment), ExportErasureLimits())
