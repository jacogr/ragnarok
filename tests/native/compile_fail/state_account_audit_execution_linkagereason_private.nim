# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "linkageReason"}

## Callers cannot forge joined authority or failed execution alternatives.
import ../../../src/state/account/audit as account_audit
var value = default(AccountAuditResult)
discard value.linkageReason
