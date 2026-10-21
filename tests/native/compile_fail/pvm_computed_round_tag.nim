# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private original-source round authority or result selection.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed_round
var candidate: ComputedRoundResult[ComputedAccumulationRound]
discard candidate.status
