# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused continuation input/state preparations expose no candidate owners or unrelated nested reasons.

import std/cmdline
import ../../src/state/[accumulation_continuation_inputs, accumulation_continuation, accumulation_operands]

let argument = paramStr(1)
let owner = default(PreparedAccumulationContinuationInputs)
let result = if argument == "default": default(AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs])
  else: prepareAccumulationContinuationInputs(default(PreparedAccumulationContinuation), default(
      AccumulationContinuationInputConfig))
case argument
of "partition": discard owner.continuationTransferPartition.value # No default owner or unrelated nested partition reason.
of "wrong-partition": discard result.partitionError # No default owner or unrelated nested partition reason.
of "inputs": discard owner.continuationInputs.value # No fabricated empty input owner.
of "state": discard owner.continuationState.value # No fabricated posterior map.
of "plan": discard owner.continuationPlan.value # No fabricated source provenance.
of "wrong-operand": discard result.operandError # InvalidPlan has no operand reason.
of "wrong-input": discard result.inputError # InvalidPlan has no grouping reason.
of "wrong-service": discard result.serviceError # InvalidPlan has no service reason.
of "wrong-batch": discard result.batchFailure # InvalidPlan has no refused parent result.
of "start": discard default(PreparedAccumulationOperands).operandReportStart.value # No fabricated range origin.
else: discard result.value # Both default and refused constructors require selected success.
