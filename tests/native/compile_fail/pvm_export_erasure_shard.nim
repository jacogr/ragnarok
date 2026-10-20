# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached trees or substituted full-width row/shard coordinates.

# @@Verification={"group": "nominal", "expected": "ErasureShardIndex", "early": ["exportErasureChunk(", "[2] expected: ErasureShardIndex but got: OriginalShardIndex"]}

import ../../../src/state/[export_erasure, export_commitment, erasure_layout, erasure_words]
discard exportErasureChunk(default(ExportErasure), OriginalShardIndex(0), ExportErasureIndex(0))
