# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge completed anchor certificates or retag failed results.
import ../../../src/state/report_anchors
let owner = default(ReportAnchorResult[AnchoredReports])
discard owner.status # Must fail before lowering.
