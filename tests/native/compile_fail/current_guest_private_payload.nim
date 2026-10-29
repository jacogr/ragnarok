# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current guest result and parent refusal storage stay private.
import ../../../src/state/accumulation/[guest_runner as accumulation_guest_runner,
    inputs as accumulation_inputs]
import ../../../src/state/store
import ../../../src/codec/header
import ../../../src/codec/state/safrole as state_safrole
import ../../../src/chain/parameters
let refused = runAccumulationGuests(default(PreparedAccumulationInputs), default(
    StateStoreSnapshot), HeaderSlot(0),
  default(StateEntropyWord), default(Parameters), default(AccumulationGuestLimits))
discard refused.completed
