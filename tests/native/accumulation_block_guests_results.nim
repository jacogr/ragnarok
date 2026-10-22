# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused block guest results expose no successful owners or inactive failure payloads.
import std/cmdline
import ../../src/state/[accumulation_block_guests, accumulation_guest_runner, accumulation_round]
import ../../src/chain/parameters
let refused = runBlockAccumulationGuests(default(BlockAccumulationRound), default(Parameters),
    default(AccumulationGuestLimits))
let empty = default(BlockGuestResult[BlockAccumulationGuests])
case paramStr(1)
of "refused": discard refused.value # A genuine InvalidRound cannot expose coverage.
of "reason": discard refused.guestFailure # A preflight refusal has no core failure payload.
of "round": discard default(BlockAccumulationGuests).guestRound.value # Default source has no round authority.
of "coverage": discard default(BlockAccumulationGuests).guestCoverage.value # Default source has no complete providers.
else: discard empty.value # Default results cannot fabricate a bound owner.
