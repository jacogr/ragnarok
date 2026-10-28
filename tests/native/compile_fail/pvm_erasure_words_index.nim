# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject nominal word, shard and resource-policy substitutions.

# @@Verification={"group": "nominal", "expected": "ErasureShardIndex", "early": ["codeWord(", "[2] expected: ErasureShardIndex but got: OriginalShardIndex"]}

import ../../../src/state/erasure_words as state_erasure_words
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
discard codeWord(default(ErasureWordCode), OriginalShardIndex(0))
