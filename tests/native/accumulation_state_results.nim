# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused atomic state results expose no published snapshot or unselected nested failure.

import std/cmdline
import ../../src/state/[accumulation_state, accumulation_finalization, accumulation_completion, store]

let argument = paramStr(1)
var target: StateStore
let outcome = if argument == "default": default(AccumulationStateResult)
  else: applyAccumulationState(target, default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits))
case argument
of "state": discard outcome.stateError # Invalid source did not inspect the target.
of "composition": discard outcome.compositionFailure # No composition was selected.
of "publication": discard outcome.publicationFailure # No publication was selected.
else: discard outcome.value # Defaults and refused sources cannot expose successful snapshots.
