# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused completed-history output projections cannot expose pairs, roots or unrelated reasons.

import std/cmdline
import ../../src/state/[accumulation_outputs, accumulation_execution,
  accumulation_continuation_execution, accumulation_reentry]
import ../../src/codec/state_outputs

let argument = paramStr(1)
let owner = default(PreparedAccumulationOutputs)
let result = if argument == "default": default(AccumulationOutputsResult[PreparedAccumulationOutputs])
  else: prepareAccumulationOutputs(default(CompletedBlockAccumulation), default(
      AccumulationOutputLimits))
case argument
of "continuation": discard owner.outputsContinuation.value # No fabricated first continuation.
of "reentry": discard owner.outputsReentry.value # No fabricated last reentry.
of "continuation-source":
  discard prepareAccumulationOutputs(default(CompletedAccumulationContinuation),
    default(AccumulationOutputHistoryLimits)).value # Invalid owners carry no pair set.
of "reentry-source":
  discard prepareAccumulationOutputs(default(CompletedAccumulationReentry),
    default(AccumulationOutputHistoryLimits)).value # No default chain can manufacture empty outputs.
of "info": discard owner.outputsInfo.value # No fabricated cardinality/extent.
of "source": discard owner.outputsSource.value # No fabricated admitted completion.
of "index": discard owner.outputAt(OutputLogIndex(0)).value # No absent default commitment.
of "entry": discard owner.outputsEntry.value # No fabricated empty C(16) encoding.
of "root": discard owner.outputsRoot.value # No fake all-zero history root.
of "wrong-history": discard result.historyError # InvalidSource is not a selected history refusal.
else: discard result.value # Default/refused projection results require selected success.
