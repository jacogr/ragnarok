# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted nominal policy/index types.

# @@Verification={"group": "nominal", "expected": "OriginalShardIndex", "early": ["originalChunk(", "[2] expected: OriginalShardIndex but got: ErasureShards"]}

import ../../../src/state/erasure/layout as erasure_layout
import ../../../src/state/[auditable_bundle, input_refinement]
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
discard originalChunk(default(ErasureLayout), ErasureShards(0))
