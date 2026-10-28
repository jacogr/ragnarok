# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime result-access executable for default/refused accumulation operand preparation.
##
## A command-line selector probes group, operand, source, prefix and bound provenance extraction;
## each path must fail at its selected-success contract rather than expose a default value.

import std/cmdline
import ../../src/state/accumulation_operands as state_accumulation_operands
import ../../src/state/accumulation_queue as state_accumulation_queue
# Runtime selection prevents default extraction from becoming a compile-time-only rejection.
let outcome = if paramStr(1) == "refused":
  prepareAccumulationOperands(default(AccumulationQueuePlan), AccumulationReportPrefix(0), default(AccumulationOperandConfig))
else: default(AccumulationOperandResult[PreparedAccumulationOperands]) # No fabricated successful plan.
let owner = default(PreparedAccumulationOperands)
case paramStr(1)
of "count": discard owner.operandServiceCount.value # No default empty service list.
of "group": discard owner.operandServiceAt(OperandServiceIndex(0)).value # No default service metadata.
of "operand": discard owner.serviceOperandAt(OperandServiceIndex(0), ServiceOperandIndex(
    0)).value # No default payload owner.
of "source": discard owner.operandQueue.value # No fabricated priority source.
of "prefix": discard owner.operandReportPrefix.value # No default selected prefix.
of "bound": discard default(BlockAccumulationOperands).operandProjection.value # No fabricated bound projection.
of "provenance": discard default(BlockAccumulationOperands).operandBlockQueue.value # No forged admission-derived queue.
else: discard outcome.value # Default/refused alternatives carry no prepared inputs.
