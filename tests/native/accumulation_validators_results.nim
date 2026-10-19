# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Uninitialized/refused validator certificates cannot expose sources, maps, observations or unrelated nested reasons.

import std/cmdline
import ../../src/state/[accumulation_validators, accumulation_times]

let argument = paramStr(1)
let owner = default(PreparedAccumulationValidators)
let outcome = if argument == "default": default(AccumulationValidatorsResult[PreparedAccumulationValidators])
  else: prepareAccumulationValidators(default(PreparedAccumulationTimes), default(
      AccumulationValidatorsConfig))
case argument
of "source": discard owner.accumulationValidatorsSource.value # No default authenticated timestamp candidate.
of "observations": discard owner.accumulationValidatorsObservations.value # No fabricated header/time/body observations.
of "projection": discard owner.accumulationValidatorsProjection.value # No fabricated zero epoch rows.
of "state": discard owner.accumulationValidatorsState.value # No default complete map.
of "wrong-roster": discard outcome.rosterError # RosterFailure is not selected.
of "wrong-activity": discard outcome.activityError # ActivityFailure is not selected.
of "wrong-projection": discard outcome.projectionError # ProjectionFailure is not selected.
else: discard outcome.value # No stale success on default/refused input.
