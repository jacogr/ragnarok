# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: prevent retagging a failed reports read as success.
## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/chain/reports
var decoded = default(ReportReadResult)
decoded.status = ReportReadError.None
