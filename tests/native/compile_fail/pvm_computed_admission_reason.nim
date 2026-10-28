# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private source-bound admission and result selection.

# @@Verification={"group": "privacy", "expected": "admissionReason"}

import ../../../src/state/computed_admission as state_computed_admission
var candidate: ComputedAdmissionResult[AdmittedComputedReports]
discard candidate.admissionReason
