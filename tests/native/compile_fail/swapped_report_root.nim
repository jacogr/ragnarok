# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A package identity cannot be initialized with an exported-segment commitment.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal","expected": "got: ReportHash[2] but wanted: ReportHash[0]"}

import ../../../src/codec/work/report as work_report
let wrong = ReportHeader(packageHash: SegmentRoot())
discard wrong
