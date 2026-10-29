# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject nominal word, shard and resource-policy substitutions.

# @@Verification={"group": "nominal", "expected": "FieldProductLimit", "early": ["requireProducts(", "[1] expected: FieldProductLimit but got: ElementLimit"]}

import ../../../src/state/erasure/[words as erasure_words, layout as erasure_layout]
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
proc requireProducts(value: FieldProductLimit) =
  ## Accept only field-product policy.
  discard
requireProducts(ElementLimit(100))
