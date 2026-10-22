# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationForget(","[5] expected: ServiceIndex but got: AccountSlot"]}

## An account creation slot cannot select a preimage request mutation target.
import ../../../src/state/accumulation_effects
import ../../../src/codec/[composite, state_accounts, state_requests, state_service_values]
import ../../../src/chain/parameters

discard recordAccumulationForget(default(AccumulationEffects), default(ServicePreimageHash),
    RequestLength(3), default(Parameters), AccountSlot(0))
