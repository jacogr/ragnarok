# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused continuation bootstraps expose neither owners nor unrelated nested reasons.

import std/cmdline
import ../../src/state/accumulation/continuation/[
    invocation as accumulation_continuation_invocation, inputs as accumulation_continuation_inputs]
import ../../src/state/accumulation/[inputs as accumulation_inputs, service as accumulation_service,
    invocation as accumulation_invocation]

let argument = paramStr(1)
let owner = default(ContinuationAccumulationInvocation)
let result = if argument == "default":
    default(AccumulationContinuationInvocationResult[ContinuationAccumulationInvocation])
  else:
    prepareContinuationAccumulationInvocation(default(PreparedAccumulationContinuationInputs),
      InvocationServiceIndex(0), default(AccumulationServiceConfig), ServiceProbeLimit(1))
case argument
of "projection": discard owner.bootstrapProjection.value # No fabricated pure bootstrap.
of "source": discard owner.bootstrapContinuation.value # No fabricated posterior continuation.
of "wrong-service": discard result.serviceError # InvalidInputs carries no nested service failure.
of "wrong-invocation": discard result.invocationError # InvalidInputs carries no nested entropy/bootstrap failure.
else: discard result.value # Both default and refused results require selected success.
