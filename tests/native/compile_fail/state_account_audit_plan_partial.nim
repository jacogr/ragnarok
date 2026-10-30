# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"StateInventory","early":["planAccountAudit(","[1] expected: StateInventory but got: StateStoreSnapshot"],"rationale":"Whole-state account auditing must demand complete logical inventory; accepting a partial StateStoreSnapshot would omit absent accounts and preimages while planning an exhaustive audit.","reference":"src/state/account/audit/plan.nim"}

## Raw mappings cannot bypass complete logical inventory provenance for exhaustive planning.
import ../../../src/state/account/audit/plan as account_audit_plan
import ../../../src/state/store
discard planAccountAudit(default(StateStoreSnapshot), AccountAuditLimits())
