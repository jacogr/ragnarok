# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused results cannot expose a state-backed package certificate.
import std/[cmdline, syncio]
import ../../src/state/[report_packages, report_anchors]
let outcome = if paramStr(1) == "error":
  checkReportPackages(default(RecentAnchoredReports), default(ReportPackageConfig))
else:
  default(ReportPackageResult[PackageCheckedReports]) # No fabricated default admission.
discard outcome.value # Both alternatives must fail the success precondition.
