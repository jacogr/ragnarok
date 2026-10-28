# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused later runners cannot expose completion or an unselected child reason.

import std/cmdline
import ../../src/state/accumulation_later_runner as state_accumulation_later_runner
import ../../src/state/accumulation_runner as state_accumulation_runner
import ../../src/state/accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
import ../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../src/chain/parameters as chain_parameters

let argument = paramStr(1)

proc checkContinuation() =
  ## Exercise guarded extraction for the continuation result instantiation.
  let outcome = if argument == "continuation-default": default(AccumulationLaterRunnerResult[CompletedAccumulationContinuation])
    else: runAccumulationContinuation(default(PreparedAccumulationContinuationInputs), default(
        Parameters), default(AccumulationRunnerLimits))
  case argument
  of "continuation-service": discard outcome.serviceError # A different reason is selected.
  of "continuation-invocation": discard outcome.invocationError # A different reason is selected.
  of "continuation-context": discard outcome.contextError # A different reason is selected.
  of "continuation-machine": discard outcome.machineError # A different reason is selected.
  of "continuation-skip": discard outcome.skipError # A different reason is selected.
  of "continuation-dispatch": discard outcome.dispatchFailure # A different reason is selected.
  of "continuation-continuation": discard outcome.continuationFailure # A different reason is selected.
  of "continuation-reentry": discard outcome.reentryFailure # A different reason is selected.
  else: discard outcome.value # Neither default nor refused ownership is complete.

proc checkReentry() =
  ## Exercise guarded extraction for the reentry result instantiation.
  let outcome = if argument == "reentry-default": default(AccumulationLaterRunnerResult[CompletedAccumulationReentry])
    else: runAccumulationReentry(default(PreparedAccumulationReentry), default(Parameters), default(AccumulationRunnerLimits))
  case argument
  of "reentry-service": discard outcome.serviceError # A different reason is selected.
  of "reentry-invocation": discard outcome.invocationError # A different reason is selected.
  of "reentry-context": discard outcome.contextError # A different reason is selected.
  of "reentry-machine": discard outcome.machineError # A different reason is selected.
  of "reentry-skip": discard outcome.skipError # A different reason is selected.
  of "reentry-dispatch": discard outcome.dispatchFailure # A different reason is selected.
  of "reentry-continuation": discard outcome.continuationFailure # A different reason is selected.
  of "reentry-reentry": discard outcome.reentryFailure # A different reason is selected.
  else: discard outcome.value # Neither default nor refused ownership is complete.

case argument
of "continuation-default", "continuation-refused", "continuation-service",
    "continuation-invocation", "continuation-context", "continuation-machine", "continuation-skip",
    "continuation-dispatch", "continuation-continuation", "continuation-reentry": checkContinuation() # Check the actual concrete result type.
of "reentry-default", "reentry-refused", "reentry-service", "reentry-invocation", "reentry-context",
    "reentry-machine", "reentry-skip", "reentry-dispatch", "reentry-continuation",
    "reentry-reentry": checkReentry() # Check the actual concrete result type.
else: discard # Runner launches only source-declared cases.
