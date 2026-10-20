# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable raw guarantees cannot replace closed verified computed envelopes.

# @@Verification={"group": "nominal", "expected": "openArray", "early": ["prepareComputedBatch(", "[1] expected: openArray but got: array"]}

import ../../../src/state/computed_batch
import ../../../src/codec/guarantees
discard prepareComputedBatch([default(Guarantee)], ComputedBatchLimits())
