# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused continuation plans cannot expose partial prefix facts or retained report/source owners.

import std/cmdline
import ../../src/state/[accumulation_continuation, accumulation_execution]

let argument = paramStr(1)
let owner = default(PreparedAccumulationContinuation)
let result = if argument == "default": default(AccumulationContinuationResult[PreparedAccumulationContinuation])
  else: planAccumulationContinuation(default(CompletedBlockAccumulation), default(
      AccumulationContinuationLimits))
case argument
of "pending": discard owner.continuationPending.value # Default plans have no producer-bound pending owner.
of "info": discard owner.continuationInfo.value # No fabricated prefix or budget.
of "source": discard owner.continuationSource.value # No synthetic admitted execution.
of "transfers": discard owner.continuationTransfers.value # No caller-substituted outgoing collection.
of "index": discard owner.continuationReportAt(ContinuationReportIndex(0)).value # No default report owner.
else: discard result.value # Both default and invalid-source results require selected success.
