# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CompletedCurrentAccumulationSequence but got: CurrentAccumulationSequence", "early": ["prepareCurrentAccumulationStatistics(", "[1] expected: CompletedCurrentAccumulationSequence but got: CurrentAccumulationSequence"]}

## Terminal source and dictionary ordinal domains cannot be replaced with active history or entry indices.
import ../../../src/state/accumulation_current_statistics as state_accumulation_current_statistics
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
discard prepareCurrentAccumulationStatistics(default(CurrentAccumulationSequence), default(CurrentAccumulationStatisticsLimits))
