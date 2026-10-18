# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge package certificates or retag failed results.
import ../../../src/state/report_packages
let owner = default(PackageCheckedReports)
discard owner.data # Must fail before lowering.
