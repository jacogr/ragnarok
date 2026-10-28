# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge completed anchor certificates or retag failed results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/report_anchors as state_report_anchors
let owner = default(ReportAnchorResult[AnchoredReports])
discard owner.status # Must fail before lowering.
