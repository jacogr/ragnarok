# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused results cannot expose a state-backed package certificate.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[cmdline, syncio]
import ../../src/state/report/[packages as report_packages, anchors as report_anchors]
let outcome = if paramStr(1) == "error":
  checkReportPackages(default(RecentAnchoredReports), default(ReportPackageConfig))
else:
  default(ReportPackageResult[PackageCheckedReports]) # No fabricated default admission.
discard outcome.value # Both alternatives must fail the success precondition.
