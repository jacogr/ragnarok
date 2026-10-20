# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached trees or substituted full-width row/shard coordinates.

# @@Verification={"group": "nominal", "expected": "ExportErasureIndex", "early": ["exportErasureChunk(", "[3] expected: ExportErasureIndex but got: ExportPageIndex"]}

import ../../../src/state/[export_erasure, export_commitment, erasure_layout, erasure_words]
discard exportErasureChunk(default(ExportErasure), ErasureShardIndex(0), ExportPageIndex(0))
