# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged complete-report/result storage access.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/report as computed_report
var candidate: ComputedWorkReport
discard candidate.data
