# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged lookup-chain storage or result alternatives.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/lookup as computed_lookup
var candidate: LookupAnchoredComputedReport
discard candidate.data
