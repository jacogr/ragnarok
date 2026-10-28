# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and invalid finalization results cannot expose maps, terminal progress or unrelated reasons.

import std/cmdline
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/state/accumulation_outputs as state_accumulation_outputs
import ../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
import ../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../src/state/accumulation_driver as state_accumulation_driver

let argument = paramStr(1)
let owner = default(PreparedFinalAccumulation)
let stopped = default(StoppedAccumulation)
let refused = prepareFinalAccumulation(default(CompletedAccumulationReentry),
  default(AccumulationOutputHistoryLimits))
let outcome = if argument == "default": default(AccumulationFinalizationResult[PreparedFinalAccumulation])
  else: refused
case argument
of "default": discard outcome.value # Default is not success.
of "info": discard owner.finalAccumulationInfo.value # No fabricated terminal progress.
of "outputs": discard owner.finalAccumulationOutputs.value # No fabricated output union.
of "state": discard owner.finalAccumulationState.value # No fabricated complete-map snapshot.
of "queue": discard owner.finalAccumulationQueue.value # No fabricated original execution queue.
of "admission": discard owner.finalAccumulationAdmission.value # No fabricated authenticated block/profile.
of "parent": discard owner.finalAccumulationParent.value # No fabricated original complete-map parent.
of "stopped": discard prepareFinalAccumulation(stopped, default(
    AccumulationOutputHistoryLimits)).value
of "wrong-output": discard refused.outputError # InvalidSource is not a selected output refusal.
of "wrong-state": discard refused.stateError # InvalidSource is not a selected store refusal.
of "continuation":
  discard prepareFinalAccumulation(default(CompletedAccumulationContinuation),
    default(AccumulationOutputHistoryLimits)).value # Default continuation cannot certify an empty terminal history.
else: discard refused.value # Failed results carry only the selected reason.
