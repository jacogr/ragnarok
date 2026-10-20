# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged transcript storage and result alternatives.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_guarantee
var candidate: ComputedGuaranteeTranscript
discard candidate.data
