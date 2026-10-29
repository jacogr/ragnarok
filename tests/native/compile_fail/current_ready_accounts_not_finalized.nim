# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationFinalization but got: PreparedCurrentAccumulationAccounts", "early": ["prepareCurrentAccumulationReady(", "[1] expected: PreparedCurrentAccumulationFinalization but got: PreparedCurrentAccumulationAccounts"]}

## Exact current finalization ownership is required.
import ../../../src/state/accumulation/current/ready as accumulation_current_ready
import ../../../src/state/accumulation/ready as accumulation_ready
import ../../../src/state/accumulation/current/accounts as accumulation_current_accounts
discard prepareCurrentAccumulationReady(default(PreparedCurrentAccumulationAccounts), default(AccumulationReadyConfig))
