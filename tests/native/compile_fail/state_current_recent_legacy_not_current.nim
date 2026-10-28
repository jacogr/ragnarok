# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationReady but got: PreparedAccumulationReady", "early": ["prepareCurrentAccumulationRecent(", "[1] expected: PreparedCurrentAccumulationReady but got: PreparedAccumulationReady"]}

## Current ready ownership cannot be substituted with a different completion domain.
import ../../../src/state/accumulation_current_recent as state_accumulation_current_recent
import ../../../src/state/accumulation_recent as state_accumulation_recent
import ../../../src/state/accumulation_ready as state_accumulation_ready
discard prepareCurrentAccumulationRecent(default(PreparedAccumulationReady), default(AccumulationRecentConfig))
