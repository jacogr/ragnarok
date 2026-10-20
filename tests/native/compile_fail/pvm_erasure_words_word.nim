# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject nominal word, shard and resource-policy substitutions.

# @@Verification={"group": "nominal", "expected": "openArray", "early": ["encodeErasureWords(", "[1] expected: openArray but got: array[0..2, uint16]"]}

import ../../../src/state/[erasure_words, erasure_layout]
import ../../../src/codec/[bounded, work_report]
discard encodeErasureWords([0'u16, 1, 2], ErasureShards(6), ErasureWordLimits())
