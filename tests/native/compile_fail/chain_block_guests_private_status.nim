# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refused block guest storage stays private, including inactive alternatives.
import ../../../src/state/accumulation_block_guests as state_accumulation_block_guests
import ../../../src/state/accumulation_guest_runner as state_accumulation_guest_runner
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/chain/parameters as chain_parameters
let refused = runBlockAccumulationGuests(default(BlockAccumulationRound), default(Parameters),
    default(AccumulationGuestLimits))
discard refused.status
