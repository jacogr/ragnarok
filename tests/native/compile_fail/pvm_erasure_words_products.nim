# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject nominal word, shard and resource-policy substitutions.

# @@Verification={"group": "nominal", "expected": "FieldProductLimit", "early": ["requireProducts(", "[1] expected: FieldProductLimit but got: ElementLimit"]}

import ../../../src/state/erasure_words as state_erasure_words
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
proc requireProducts(value: FieldProductLimit) =
  ## Accept only field-product policy.
  discard
requireProducts(ElementLimit(100))
