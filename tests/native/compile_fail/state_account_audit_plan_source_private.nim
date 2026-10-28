# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "source"}

## Caller cannot substitute source/quotas or retag a failed frozen plan.
import ../../../src/state/account_audit_plan as state_account_audit_plan
var value = default(StateAccountAuditPlan)
discard value.source
