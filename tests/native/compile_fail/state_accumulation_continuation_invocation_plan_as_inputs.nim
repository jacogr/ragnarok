# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationContinuationInputs", "early": ["prepareContinuationAccumulationInvocation(", "[1] expected: PreparedAccumulationContinuationInputs but got: PreparedAccumulationContinuation"]}

## Reject replacement of nominal continuation invocation provenance.

import ../../../src/state/accumulation_continuation_invocation as state_accumulation_continuation_invocation
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
var plan: PreparedAccumulationContinuation
discard prepareContinuationAccumulationInvocation(plan, InvocationServiceIndex(0),
  default(AccumulationServiceConfig), ServiceProbeLimit(1))
