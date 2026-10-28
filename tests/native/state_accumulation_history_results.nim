# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default or refused accumulated-history results cannot expose projections, maps or unrelated failure reasons.

import std/cmdline
import ../../src/state/accumulation_history as state_accumulation_history
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/codec/state_workqueues as codec_state_workqueues

let argument = paramStr(1)
let owner = default(PreparedAccumulationHistory)
let outcome = if argument == "default": default(AccumulationHistoryResult[PreparedAccumulationHistory])
  else: prepareAccumulationHistory(default(PreparedFinalAccumulation), default(
      AccumulationHistoryConfig))
case argument
of "projection":
  discard projectAccumulationHistory(default(AccumulatedSnapshot), [],
    default(AccumulationHistoryConfig)).value # A missing input owner never yields an initialized projection.
of "info": discard owner.accumulationHistoryInfo.value # No fabricated counts.
of "source": discard owner.accumulationHistorySource.value # No fabricated finalization.
of "ring": discard owner.accumulationHistoryRing.value # No fabricated complete history ring.
of "state": discard owner.accumulationHistoryState.value # No fabricated full-state candidate.
of "entry": discard owner.accumulationHistoryEntry.value # No fabricated canonical bytes.
of "wrong-codec": discard outcome.codecError # InvalidSource/default is not a selected codec refusal.
of "wrong-state": discard outcome.stateError # InvalidSource/default is not a selected state refusal.
else: discard outcome.value # Defaults and refused candidates carry reasons alone.
