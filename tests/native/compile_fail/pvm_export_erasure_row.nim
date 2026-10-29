# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached trees or substituted full-width row/shard coordinates.

# @@Verification={"group": "nominal", "expected": "ExportErasureIndex", "early": ["exportErasureChunk(", "[3] expected: ExportErasureIndex but got: ExportPageIndex"]}

import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/export/commitment" as export_commitment
import ../../../src/state/erasure/[layout as erasure_layout, words as erasure_words]
discard exportErasureChunk(default(ExportErasure), ErasureShardIndex(0), ExportPageIndex(0))
