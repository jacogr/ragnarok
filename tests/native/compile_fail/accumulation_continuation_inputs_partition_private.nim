# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "partitionReason"}

## A refused scheduling result cannot reveal or replace its private partition discriminator payload.

import ../../../src/state/[accumulation_continuation_inputs, accumulation_continuation]
let refused = prepareAccumulationContinuationInputs(default(PreparedAccumulationContinuation),
    default(AccumulationContinuationInputConfig))
discard refused.partitionReason
