# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged complete-report/result storage access.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed_report as state_computed_report
var candidate: ComputedReportResult[ComputedWorkReport]
discard candidate.completed
