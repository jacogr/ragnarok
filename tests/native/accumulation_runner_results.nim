# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default runner results cannot expose a completed round or an unselected child reason.

import std/cmdline
import ../../src/state/[accumulation_runner, accumulation_round]
import ../../src/chain/parameters

let argument = paramStr(1)
let outcome = if argument == "default": default(AccumulationRunnerResult)
  else: runBlockAccumulation(default(BlockAccumulationRound), default(Parameters),
    default(AccumulationRunnerLimits))
case argument
of "service": discard outcome.serviceError # Wrong selected alternative must trap.
of "invocation": discard outcome.invocationError # Wrong selected alternative must trap.
of "context": discard outcome.contextError # Wrong selected alternative must trap.
of "machine": discard outcome.machineError # Wrong selected alternative must trap.
of "skip": discard outcome.skipError # Wrong selected alternative must trap.
of "dispatch": discard outcome.dispatchFailure # Wrong selected alternative must trap.
of "completion": discard outcome.completionFailure # Wrong selected alternative must trap.
else: discard outcome.value # Neither default nor invalid source is complete.
