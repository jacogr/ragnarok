# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused completion results contain no candidate or unselected failed phase.

import std/cmdline
import ../../src/state/[accumulation_completion, accumulation_driver, accumulation_finalization]

let argument = paramStr(1)
let outcome = if argument == "default": default(AccumulationCompletionResult)
  elif argument == "composition": prepareAccumulationComposition(default(PreparedFinalAccumulation),
      default(AccumulationCompositionLimits))
  else: prepareStoppedAccumulation(default(StoppedAccumulation), default(
      AccumulationCompletionLimits))
case argument
of "finalization": discard outcome.finalizationFailure # Invalid source did not select this phase.
of "history": discard outcome.historyFailure # Invalid source did not select this phase.
of "ready": discard outcome.readyFailure # Invalid source did not select this phase.
of "recent": discard outcome.recentFailure # Invalid source did not select this phase.
of "times": discard outcome.timesFailure # Invalid source did not select this phase.
of "validators": discard outcome.validatorsFailure # Invalid source did not select this phase.
of "activity": discard outcome.activityFailure # Invalid source did not select this phase.
of "preimages": discard outcome.preimagesFailure # Invalid source did not select this phase.
of "authorization": discard outcome.authorizationFailure # Invalid source did not select this phase.
of "consensus": discard outcome.consensusFailure # Invalid source did not select this phase.
else: discard outcome.value # Defaults and refused sources cannot expose successful candidates.
