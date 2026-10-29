# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationReady but got: PreparedCurrentAccumulationFinalization", "early": ["prepareCurrentAccumulationRecent(", "[1] expected: PreparedCurrentAccumulationReady but got: PreparedCurrentAccumulationFinalization"]}

## Current ready ownership cannot be substituted with a different completion domain.
import ../../../src/state/accumulation/current/recent as accumulation_current_recent
import ../../../src/state/accumulation/recent as accumulation_recent
import ../../../src/state/accumulation/current/finalization as accumulation_current_finalization
discard prepareCurrentAccumulationRecent(default(PreparedCurrentAccumulationFinalization), default(AccumulationRecentConfig))
