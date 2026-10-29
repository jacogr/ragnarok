# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused anchor results cannot expose completed report batches.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[cmdline, syncio]
import ../../src/state/report/anchors as report_anchors
import ../../src/codec/header
let outcome = if paramStr(1) == "error":
  checkReportLookupAnchors(default(RecentAnchoredReports), default(OwnedHeader), [], default(AncestorConfig))
else:
  default(ReportAnchorResult[AnchoredReports]) # No default successful chain.
discard outcome.value # Both alternatives must fail the success precondition.
