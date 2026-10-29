# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationContinuationInputs", "early": ["prepareContinuationAccumulationInvocation(", "[1] expected: PreparedAccumulationContinuationInputs but got: PreparedAccumulationContinuation"]}

## Reject replacement of nominal continuation invocation provenance.

import ../../../src/state/accumulation/continuation/invocation as accumulation_continuation_invocation
import ../../../src/state/accumulation/[continuation as accumulation_continuation,
    inputs as accumulation_inputs, service as accumulation_service,
    invocation as accumulation_invocation]
var plan: PreparedAccumulationContinuation
discard prepareContinuationAccumulationInvocation(plan, InvocationServiceIndex(0),
  default(AccumulationServiceConfig), ServiceProbeLimit(1))
