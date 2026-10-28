# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current round result tags and inactive parent payloads remain private.
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/accumulation_current_round as state_accumulation_current_round
import ../../../src/state/accumulation_round as state_accumulation_round
let refused = runCurrentBlockAccumulationRound(default(BlockAccumulationRound), default(Parameters),
    default(CurrentAccumulationRoundLimits))
discard refused.completed
