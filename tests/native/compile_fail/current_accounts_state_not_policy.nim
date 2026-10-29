# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: AccumulationAccountConfig but got: StateStoreSnapshot", "early": ["prepareCurrentAccumulationAccounts(", "[2] expected: AccumulationAccountConfig but got: StateStoreSnapshot"]}

## Timestamp provenance and caller-state boundaries are nominal.
import ../../../src/state/accumulation/current/accounts as accumulation_current_accounts
import ../../../src/state/accumulation/accounts as accumulation_accounts
import ../../../src/state/accumulation/current/statistics as accumulation_current_statistics
import ../../../src/state/store
discard prepareCurrentAccumulationAccounts(default(PreparedCurrentAccumulationStatistics), default(StateStoreSnapshot))
