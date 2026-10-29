# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject nominal word, shard and resource-policy substitutions.

# @@Verification={"group": "nominal", "expected": "ErasureShardIndex", "early": ["codeWord(", "[2] expected: ErasureShardIndex but got: OriginalShardIndex"]}

import ../../../src/state/erasure/[words as erasure_words, layout as erasure_layout]
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
discard codeWord(default(ErasureWordCode), OriginalShardIndex(0))
