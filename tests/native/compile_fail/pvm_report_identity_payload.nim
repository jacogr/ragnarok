# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private report identity storage or success forgery.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/report_identity as state_report_identity
var outcome: ReportIdentityResult[int]
discard outcome.completed
