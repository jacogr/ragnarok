# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: StatisticsServiceIndex but got: CurrentSequenceEntryIndex", "early": ["currentStatisticsAt(", "[2] expected: StatisticsServiceIndex but got: CurrentSequenceEntryIndex"]}

## Terminal source and dictionary ordinal domains cannot be replaced with active history or entry indices.
import ../../../src/state/[accumulation_current_statistics, accumulation_current_sequence]
discard currentStatisticsAt(default(PreparedCurrentAccumulationStatistics),
    CurrentSequenceEntryIndex(0))
