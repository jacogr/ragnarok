# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refused block guest storage stays private, including inactive alternatives.
import ../../../src/state/[accumulation_block_guests, accumulation_guest_runner, accumulation_round]
import ../../../src/chain/parameters
let refused = runBlockAccumulationGuests(default(BlockAccumulationRound), default(Parameters),
    default(AccumulationGuestLimits))
discard refused.status
