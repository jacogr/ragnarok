# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateEconomicProfile", "early": ["buildEconomicsTable(", "[3] expected: StateEconomicProfile but got: AccountDepositSchedule"]}

## Raw arithmetic rates cannot replace explicit selected valid parameter evidence.
import ../../../src/state/[economics_table, footprint_audit]
import ../../../src/state/service/directory as service_directory
import ../../../src/state/account/deposit as account_deposit
discard buildEconomicsTable(default(CheckedAccountFootprints), default(StateServiceDirectory),
    AccountDepositSchedule(), EconomicsTableLimits())
