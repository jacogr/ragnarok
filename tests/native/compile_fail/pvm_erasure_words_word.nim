# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject nominal word, shard and resource-policy substitutions.

# @@Verification={"group": "nominal","expected": "openArray","early": ["encodeErasureWords(","[1] expected: openArray[ErasureWord] but got: array[0..2, uint16]"]}

import ../../../src/state/erasure_words as state_erasure_words
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
discard encodeErasureWords([0'u16, 1, 2], ErasureShards(6), ErasureWordLimits())
