# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current sequences and plans expose no successful source/history/input or inactive parent reason.
import std/cmdline
import ../../src/state/[accumulation_current_sequence, accumulation_current_round]
let owner = default(CurrentSequenceResult[PreparedCurrentContinuation])
let refusedSource = startCurrentAccumulationSequence(default(PreparedCurrentAccumulationRound))
let sequence = default(CurrentAccumulationSequence)
let plan = default(PreparedCurrentContinuation)
let refusedPlan = planCurrentAccumulationContinuation(sequence, default(CurrentContinuationLimits))
let refusedRun = runCurrentAccumulationContinuation(plan, default(
    CurrentContinuationExecutionLimits))
case paramStr(1)
of "refused-sequence": discard refusedSource.value # Only genuine selected success/failure authorizes this extraction.
of "refused-plan": discard refusedPlan.value # Only genuine selected success/failure authorizes this extraction.
of "operand": discard owner.operandFailure # Only genuine selected success/failure authorizes this extraction.
of "input": discard owner.inputFailure # Only genuine selected success/failure authorizes this extraction.
of "partition": discard owner.partitionFailure # Only genuine selected success/failure authorizes this extraction.
of "sequence-info": discard sequence.currentSequenceInfo.value # Only genuine selected success/failure authorizes this extraction.
of "sequence-initial": discard sequence.currentSequenceInitial.value # Only genuine selected success/failure authorizes this extraction.
of "sequence-latest": discard sequence.currentSequenceLatestState.value # Only genuine selected success/failure authorizes this extraction.
of "sequence-pending": discard sequence.currentSequencePending.value # Only genuine selected success/failure authorizes this extraction.
of "sequence-coverage": discard sequence.currentSequenceCoverageAt(CurrentSequenceEntryIndex(
    0)).value # Only genuine selected success/failure authorizes this extraction.
of "sequence-outputs": discard sequence.currentSequenceOutputsAt(CurrentSequenceEntryIndex(
    0)).value # Only genuine selected success/failure authorizes this extraction.
of "sequence-state": discard sequence.currentSequenceStateAt(CurrentSequenceEntryIndex(
    0)).value # Only genuine selected success/failure authorizes this extraction.
of "plan-info": discard plan.currentContinuationInfo.value # Only genuine selected success/failure authorizes this extraction.
of "plan-source": discard plan.currentContinuationSource.value # Only genuine selected success/failure authorizes this extraction.
of "plan-inputs": discard plan.currentContinuationInputs.value # Only genuine selected success/failure authorizes this extraction.
of "plan-partition": discard plan.currentContinuationPartition.value # Only genuine selected success/failure authorizes this extraction.
of "plan-state": discard plan.currentContinuationState.value # Only genuine selected success/failure authorizes this extraction.
of "plan-report": discard plan.currentContinuationReportAt(CurrentPlanReportIndex(
    0)).value # Only genuine selected success/failure authorizes this extraction.
of "entry-guest": discard owner.guestFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-account": discard owner.accountFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-provision": discard owner.provisionFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-global": discard owner.globalFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-output": discard owner.outputFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-transfer": discard owner.transferFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-pending": discard owner.pendingFailure # Only the actual later-execution failure branch grants its parent reason.
of "entry-refused": discard refusedRun.value # A refused/default plan never completes a fake entry.
else: discard owner.value # No fabricated initialized current continuation.
