# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge package certificates or retag failed results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/state/report_packages
let owner = default(ReportPackageResult[PackageCheckedReports])
discard owner.status # Must fail before lowering.
