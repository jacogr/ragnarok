# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass the private report state through status.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/codec/composite
import ../../../src/codec/work/report as work_report
import ../../../src/codec/report_owned
var value = default(ReportHeaderResult)
discard ReportHeaderResult(status: CompositeError.None)
