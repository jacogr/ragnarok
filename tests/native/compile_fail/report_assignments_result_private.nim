# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge assignment candidates or retag failed planning results.
import ../../../src/state/report_assignments
let owner = default(ReportAssignmentResult[ReportAssignmentPlan])
discard owner.completed # Must fail before lowering.
