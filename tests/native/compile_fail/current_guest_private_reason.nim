# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "serviceReason"}

## Current guest result and parent refusal storage stay private.
import ../../../src/state/[accumulation_guest_runner, accumulation_inputs, store]
import ../../../src/codec/[header, state_safrole]
import ../../../src/chain/parameters
let refused = runAccumulationGuests(default(PreparedAccumulationInputs), default(
    StateStoreSnapshot), HeaderSlot(0),
  default(StateEntropyWord), default(Parameters), default(AccumulationGuestLimits))
discard refused.serviceReason
