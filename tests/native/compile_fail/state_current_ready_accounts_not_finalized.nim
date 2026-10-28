# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationFinalization but got: PreparedCurrentAccumulationAccounts", "early": ["prepareCurrentAccumulationReady(", "[1] expected: PreparedCurrentAccumulationFinalization but got: PreparedCurrentAccumulationAccounts"]}

## Exact current finalization ownership is required.
import ../../../src/state/accumulation_current_ready as state_accumulation_current_ready
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_current_accounts as state_accumulation_current_accounts
discard prepareCurrentAccumulationReady(default(PreparedCurrentAccumulationAccounts), default(AccumulationReadyConfig))
