# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private source-bound admission and result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/admission as computed_admission
var candidate: AdmittedComputedReports
discard candidate.data
