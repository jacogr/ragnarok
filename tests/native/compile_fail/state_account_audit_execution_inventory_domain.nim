# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateAccountAuditPlan", "early": ["executeAccountAudit(", "[1] expected: StateAccountAuditPlan but got: StateInventory"]}

## Raw inventories cannot bypass whole-predicate policy admission.
import ../../../src/state/account_audit as state_account_audit
import ../../../src/state/inventory as state_inventory
discard executeAccountAudit(default(StateInventory))
