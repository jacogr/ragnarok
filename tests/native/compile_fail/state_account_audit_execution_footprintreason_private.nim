# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "footprintReason"}

## Callers cannot forge joined authority or failed execution alternatives.
import ../../../src/state/account_audit
var value = default(AccountAuditResult)
discard value.footprintReason
