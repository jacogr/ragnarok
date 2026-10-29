# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "partitionReason"}

## A refused scheduling result cannot reveal or replace its private partition discriminator payload.

import ../../../src/state/accumulation/continuation/inputs as accumulation_continuation_inputs
import ../../../src/state/accumulation/continuation as accumulation_continuation
let refused = prepareAccumulationContinuationInputs(default(PreparedAccumulationContinuation),
    default(AccumulationContinuationInputConfig))
discard refused.partitionReason
