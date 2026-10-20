# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached trees or substituted full-width row/shard coordinates.

# @@Verification={"group": "nominal", "expected": "BundleErasure", "early": ["prepareExportErasure(", "[1] expected: BundleErasure but got: ExportCommitment"]}

import ../../../src/state/[export_erasure, export_commitment, erasure_layout, erasure_words]
discard prepareExportErasure(default(ExportCommitment), ExportErasureLimits())
