# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached trees or substituted full-width row/shard coordinates.

# @@Verification={"group": "nominal", "expected": "ErasureShardIndex", "early": ["exportErasureChunk(", "[2] expected: ErasureShardIndex but got: OriginalShardIndex"]}

import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/export/commitment" as export_commitment
import ../../../src/state/erasure/[layout as erasure_layout, words as erasure_words]
discard exportErasureChunk(default(ExportErasure), OriginalShardIndex(0), ExportErasureIndex(0))
