# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Defaults/refusals cannot expose timestamp candidates or unrelated nested failure reasons.

import std/cmdline
import ../../src/state/[accumulation_times, accumulation_recent, store]
import ../../src/codec/state_accounts

let argument = paramStr(1)
let owner = default(PreparedAccumulationTimes)
let outcome = if argument == "default": default(AccumulationTimesResult[PreparedAccumulationTimes])
  else: prepareAccumulationTimes(default(PreparedAccumulationRecent), default(
      AccumulationTimesConfig))
case argument
of "projection": discard projectAccumulationTimes(default(StateStoreSnapshot), [], AccountSlot(0),
    default(AccumulationTimesLimits)).value # Invalid maps never imply initialized empty projection.
of "info": discard owner.accumulationTimesInfo.value # No fabricated info from defaults.
of "source": discard owner.accumulationTimesSource.value # No fabricated source from defaults.
of "statistics": discard owner.accumulationTimesStatistics.value # No fabricated statistics from defaults.
of "state": discard owner.accumulationTimesState.value # No fabricated state from defaults.
of "entry": discard owner.accumulationTimeEntryAt(AccumulationTimeIndex(0)).value # No fabricated account entry.
of "wrong-statistics": discard outcome.statisticsError # StatisticsFailure is not selected.
of "wrong-metadata": discard outcome.metadataError # MetadataFailure is not selected.
of "wrong-state": discard outcome.stateError # StateFailure is not selected.
else: discard outcome.value # Defaults/refusals contain reasons alone.
