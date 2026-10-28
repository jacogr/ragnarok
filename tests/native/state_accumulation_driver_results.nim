# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default driver results and default terminal owners enforce selected extraction in optimized builds.

import std/cmdline
import ../../src/state/accumulation_driver as state_accumulation_driver
import ../../src/state/accumulation_execution as state_accumulation_execution
import ../../src/chain/parameters as chain_parameters

let argument = paramStr(1)
let outcome = if argument == "default": default(AccumulationDriverResult)
  else: driveAccumulation(default(CompletedBlockAccumulation), default(Parameters), default(
      AccumulationDriverLimits))
let stopped = default(StoppedAccumulation)
case argument
of "selection": discard outcome.selectionFailure # The result selected invalid source, not this child reason.
of "input": discard outcome.inputFailure # The result selected invalid source, not this child reason.
of "continuation": discard outcome.continuationFailure # The result selected invalid source, not this child reason.
of "preparation": discard outcome.reentryPreparationFailure # The result selected invalid source, not this child reason.
of "execution": discard outcome.reentryExecutionFailure # The result selected invalid source, not this child reason.
of "stopped-continuation": discard stopped.stoppedContinuation # Default is not a stopped continuation.
of "stopped-reentry": discard stopped.stoppedReentry # Default is not a stopped reentry.
else: discard outcome.value # Default/refused results contain no terminal history.
