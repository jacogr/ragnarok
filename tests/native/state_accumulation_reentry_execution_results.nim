# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused reentry bootstrap/completion results expose neither retained owners nor unrelated nested reasons.

import std/cmdline
import ../../src/state/accumulation_reentry_invocation as state_accumulation_reentry_invocation
import ../../src/state/accumulation_reentry_execution as state_accumulation_reentry_execution
import ../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../src/state/accumulation_execution as state_accumulation_execution
import ../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../src/state/accumulation_service as state_accumulation_service
import ../../src/state/accumulation_invocation as state_accumulation_invocation

let argument = paramStr(1)
let invocation = if argument == "inv-default": default(AccumulationReentryInvocationResult[ReentryAccumulationInvocation])
  else: prepareReentryAccumulationInvocation(default(PreparedAccumulationReentry),
      InvocationServiceIndex(0),
    default(AccumulationServiceConfig), ServiceProbeLimit(1))
let completion = if argument == "exec-default": default(AccumulationReentryExecutionResult[CompletedAccumulationReentry])
  else: completeAccumulationReentry(default(PreparedAccumulationReentry), [], [], default(
      AccumulationExecutionLimits))
let bootstrap = default(ReentryAccumulationInvocation)
let completed = default(CompletedAccumulationReentry)
case argument
of "inv-default", "inv-refused": discard invocation.value # No fabricated bound bootstrap.
of "inv-projection": discard bootstrap.bootstrapProjection.value # No fabricated pure bootstrap.
of "inv-source": discard bootstrap.bootstrapReentry.value # No fabricated reentry source.
of "inv-service": discard invocation.serviceError # InvalidInputs carries no service failure.
of "inv-reason": discard invocation.invocationError # InvalidInputs carries no entropy/bootstrap failure.
of "exec-info": discard completed.executionInfo.value # No fabricated completion facts.
of "exec-gas": discard completed.executionGasAt(InvocationServiceIndex(0)).value # No fabricated gas row.
of "exec-batch": discard completed.executionBatch.value # No usable default application batch.
of "exec-source": discard completed.executionReentry.value # No substitute completed source.
of "exec-reason": discard completion.batchFailure # InvalidInputs carries no refused batch parent.
else: discard completion.value # Both default and refused completion require selected success.
