# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationForget(","[5] expected: ServiceIndex but got: AccountSlot"]}

## An account creation slot cannot select a preimage request mutation target.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/chain/parameters as chain_parameters

discard recordAccumulationForget(default(AccumulationEffects), default(ServicePreimageHash),
    RequestLength(3), default(Parameters), AccountSlot(0))
