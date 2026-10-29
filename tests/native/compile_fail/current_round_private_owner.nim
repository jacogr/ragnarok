# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Caller code cannot construct or mutate the retained current round source graph.
import ../../../src/state/accumulation/current/round as accumulation_current_round
let owner = default(PreparedCurrentAccumulationRound)
discard owner.data
