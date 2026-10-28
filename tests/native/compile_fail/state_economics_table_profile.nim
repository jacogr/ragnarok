# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateEconomicProfile", "early": ["buildEconomicsTable(", "[3] expected: StateEconomicProfile but got: AccountDepositSchedule"]}

## Raw arithmetic rates cannot replace explicit selected valid parameter evidence.
import ../../../src/state/economics_table as state_economics_table
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/service_directory as state_service_directory
import ../../../src/state/account_deposit as state_account_deposit
discard buildEconomicsTable(default(CheckedAccountFootprints), default(StateServiceDirectory),
    AccountDepositSchedule(), EconomicsTableLimits())
