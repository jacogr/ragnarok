# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge assignment candidates or retag failed planning results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/report/assignments as report_assignments
let owner = default(ReportAssignmentPlan)
discard owner.data # Must fail before lowering.
