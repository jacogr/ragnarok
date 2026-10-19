# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused later-round completion exposes neither usable batches, source owners nor gas observations.

import std/cmdline
import ../../src/state/[accumulation_continuation_execution, accumulation_continuation_inputs,
  accumulation_execution, accumulation_inputs]

let argument = paramStr(1)
let owner = default(CompletedAccumulationContinuation)
let result = if argument == "default":
    default(AccumulationContinuationExecutionResult[CompletedAccumulationContinuation])
  else: completeAccumulationContinuation(default(PreparedAccumulationContinuationInputs), [], [],
    default(AccumulationExecutionLimits))
case argument
of "info": discard owner.executionInfo.value # No fabricated zero-gas completion facts.
of "gas": discard owner.executionGasAt(InvocationServiceIndex(0)).value # No fabricated service gas row.
of "batch": discard owner.executionBatch.value # No usable default state application batch.
of "source": discard owner.executionContinuation.value # No substitute posterior source owner.
of "wrong-batch": discard result.batchFailure # InvalidInputs has no nested failed batch.
else: discard result.value # Both default and refused completion require selected success.
