# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CheckedAccountFootprints", "early": ["observeServiceDeposit(", "[1] expected: CheckedAccountFootprints but got: StateInventory"]}

## Structurally complete inventory cannot substitute for checked dependent footprint evidence.
import ../../../src/state/[service_deposit, account_deposit, service_directory, inventory]
import ../../../src/codec/state_accounts
discard observeServiceDeposit(default(StateInventory), default(StateServiceDirectory), ServiceIndex(
    7), AccountDepositSchedule())
