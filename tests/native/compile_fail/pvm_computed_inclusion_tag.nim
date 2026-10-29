# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject mutation of private inclusion authority and result selection.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed/inclusion as computed_inclusion
var candidate: ComputedInclusionResult[IncludedComputedGuarantees]
discard candidate.status
