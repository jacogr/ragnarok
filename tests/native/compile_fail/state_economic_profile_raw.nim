# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "Parameters", "early": ["captureEconomicProfile(", "[1] expected: Parameters but got: AccountDepositSchedule"]}

## Raw mathematical rates cannot substitute for selected valid immutable parameters.
import ../../../src/state/economic_profile as state_economic_profile
import ../../../src/state/account_deposit as state_account_deposit
discard captureEconomicProfile(AccountDepositSchedule())
