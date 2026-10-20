# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached sources or substituted nominal policy/index types.

# @@Verification={"group": "nominal", "expected": "OriginalShardIndex", "early": ["originalChunk(", "[2] expected: OriginalShardIndex but got: ErasureShards"]}

import ../../../src/state/[erasure_layout, auditable_bundle, input_refinement]
import ../../../src/codec/[bounded, work_report]
discard originalChunk(default(ErasureLayout), ErasureShards(0))
