# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged lookup-chain storage or result alternatives.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed_lookup as state_computed_lookup
var candidate: ComputedLookupResult[LookupAnchoredComputedReport]
discard candidate.completed
