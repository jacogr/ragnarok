# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "failed"}

## Refused block guest storage stays private, including inactive alternatives.
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
import ../../../src/state/accumulation/[guest_runner as accumulation_guest_runner,
    round as accumulation_round]
import ../../../src/chain/parameters
let refused = runBlockAccumulationGuests(default(BlockAccumulationRound), default(Parameters),
    default(AccumulationGuestLimits))
discard refused.failed
