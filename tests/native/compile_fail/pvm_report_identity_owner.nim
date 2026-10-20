# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private report identity storage or success forgery.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/report_identity
var owner: ReportIdentity
discard owner.data
