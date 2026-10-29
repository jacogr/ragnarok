# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private original-source round authority or result selection.

# @@Verification={"group": "privacy", "expected": "roundReason"}

import ../../../src/state/computed/round as computed_round
var candidate: ComputedRoundResult[ComputedAccumulationRound]
discard candidate.roundReason
