# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current guest result and parent refusal storage stay private.
import ../../../src/state/accumulation_guest_runner as state_accumulation_guest_runner
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/store as state_store
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/chain/parameters as chain_parameters
let refused = runAccumulationGuests(default(PreparedAccumulationInputs), default(
    StateStoreSnapshot), HeaderSlot(0),
  default(StateEntropyWord), default(Parameters), default(AccumulationGuestLimits))
discard refused.completed
