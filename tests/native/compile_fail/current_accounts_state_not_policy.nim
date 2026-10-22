# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: AccumulationAccountConfig but got: StateStoreSnapshot", "early": ["prepareCurrentAccumulationAccounts(", "[2] expected: AccumulationAccountConfig but got: StateStoreSnapshot"]}

## Timestamp provenance and caller-state boundaries are nominal.
import ../../../src/state/[accumulation_current_accounts, accumulation_accounts,
    accumulation_current_statistics, store]
discard prepareCurrentAccumulationAccounts(default(PreparedCurrentAccumulationStatistics), default(StateStoreSnapshot))
