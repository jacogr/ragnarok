# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused reentry preparation exposes neither usable source/input/state owners nor unrelated nested reasons.

import std/cmdline
import ../../src/state/[accumulation_reentry, accumulation_continuation_execution, accumulation_continuation]

let argument = paramStr(1)
let owner = default(PreparedAccumulationReentry)
let result = if argument == "default": default(AccumulationReentryResult[PreparedAccumulationReentry])
  else: prepareAccumulationReentry(default(CompletedAccumulationContinuation), default(
      AccumulationReentryConfig))
case argument
of "previous": discard owner.reentryPrevious.value # Defaults have no immediate predecessor.
of "cycle-default":
  discard prepareAccumulationReentry(default(CompletedAccumulationReentry), default(
      AccumulationReentryConfig),
    AccumulationReentryDepthLimit(1)).value # No fabricated completed cycle source.
of "info": discard owner.reentryInfo.value # No fabricated empty/stopped selection.
of "source": discard owner.reentrySource.value # No fabricated completed later round.
of "transfers": discard owner.reentryTransfers.value # Defaults retain no outgoing owner.
of "inputs": discard owner.reentryInputs.value # No fabricated selected groups.
of "state": discard owner.reentryState.value # No partial successor map.
of "report": discard owner.reentryReportAt(ContinuationReportIndex(0)).value # No fabricated report handle.
of "wrong-operand": discard result.operandError # InvalidSource carries no materialization failure.
of "wrong-input": discard result.inputError # InvalidSource carries no grouping failure.
of "wrong-service": discard result.serviceError # InvalidSource carries no service failure.
of "wrong-batch": discard result.batchFailure # InvalidSource carries no refused parent batch.
else: discard result.value # Both default and refused results require selected success.
