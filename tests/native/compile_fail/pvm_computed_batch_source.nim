# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable raw guarantees cannot replace closed verified computed envelopes.

# @@Verification={"group": "nominal","expected": "openArray","early": ["prepareComputedBatch(","[1] expected: openArray[ComputedGuaranteeEnvelope] but got: array[0..0, Guarantee]"]}

import ../../../src/state/computed/batch as computed_batch
import ../../../src/codec/guarantees
discard prepareComputedBatch([default(Guarantee)], ComputedBatchLimits())
