# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateInventory", "early": ["planAccountAudit(", "[1] expected: StateInventory but got: StateStoreSnapshot"]}

## Raw mappings cannot bypass complete logical inventory provenance for exhaustive planning.
import ../../../src/state/account_audit_plan as state_account_audit_plan
import ../../../src/state/store as state_store
discard planAccountAudit(default(StateStoreSnapshot), AccountAuditLimits())
