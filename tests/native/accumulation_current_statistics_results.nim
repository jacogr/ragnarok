# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current statistics cannot reveal initialized empty values or detached terminal ownership.
import std/cmdline
import ../../src/codec/state/statistics as state_statistics
import ../../src/state/accumulation/current/[statistics as accumulation_current_statistics,
    driver as accumulation_current_driver]
let owner = default(CurrentAccumulationStatisticsResult[PreparedCurrentAccumulationStatistics])
let statistics = default(PreparedCurrentAccumulationStatistics)
let refused = prepareCurrentAccumulationStatistics(default(CompletedCurrentAccumulationSequence),
    default(CurrentAccumulationStatisticsLimits))
case paramStr(1)
of "refused": discard refused.value # Only successful complete source-bound extraction is permitted.
of "info": discard statistics.currentStatisticsInfo.value # Only successful complete source-bound extraction is permitted.
of "source": discard statistics.currentStatisticsSource.value # Only successful complete source-bound extraction is permitted.
of "row": discard statistics.currentStatisticsAt(StatisticsServiceIndex(
    0)).value # Only successful complete source-bound extraction is permitted.
else: discard owner.value # No synthetic complete statistics dictionary.
