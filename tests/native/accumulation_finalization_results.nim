# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and invalid finalization results cannot expose maps, terminal progress or unrelated reasons.

import std/cmdline
import ../../src/state/[accumulation_finalization, accumulation_outputs,
  accumulation_continuation_execution, accumulation_reentry]

let argument = paramStr(1)
let owner = default(PreparedFinalAccumulation)
let refused = prepareFinalAccumulation(default(CompletedAccumulationReentry),
  default(AccumulationOutputHistoryLimits))
let outcome = if argument == "default": default(AccumulationFinalizationResult[PreparedFinalAccumulation])
  else: refused
case argument
of "default": discard outcome.value # Default is not success.
of "info": discard owner.finalAccumulationInfo.value # No fabricated terminal progress.
of "outputs": discard owner.finalAccumulationOutputs.value # No fabricated output union.
of "state": discard owner.finalAccumulationState.value # No fabricated complete-map snapshot.
of "wrong-output": discard refused.outputError # InvalidSource is not a selected output refusal.
of "wrong-state": discard refused.stateError # InvalidSource is not a selected store refusal.
of "continuation":
  discard prepareFinalAccumulation(default(CompletedAccumulationContinuation),
    default(AccumulationOutputHistoryLimits)).value # Default continuation cannot certify an empty terminal history.
else: discard refused.value # Failed results carry only the selected reason.
