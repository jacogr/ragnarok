# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and invalid finalized statistics cannot expose rows, totals or retained state provenance.

import std/cmdline
import ../../src/state/accumulation_statistics as state_accumulation_statistics
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/codec/state_statistics as codec_state_statistics

let argument = paramStr(1)
let owner = default(PreparedAccumulationStatistics)
let outcome = if argument == "default": default(AccumulationStatisticsResult[PreparedAccumulationStatistics])
  else: prepareAccumulationStatistics(default(PreparedFinalAccumulation), default(
      AccumulationStatisticsLimits))
case argument
of "info": discard owner.statisticsInfo.value # No fabricated aggregate gas or row counts.
of "source": discard owner.statisticsSource.value # No fabricated final full-state certificate.
of "index": discard owner.statisticsAt(StatisticsServiceIndex(0)).value # No fabricated service activity.
else: discard outcome.value # Default and refused preparation require selected success.
