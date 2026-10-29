# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationSolicit(","[5] expected: ServiceIndex but got: AccountSlot"]}

## An account creation slot cannot select a preimage request mutation target.
import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
import ../../../src/codec/state/[accounts as state_accounts, requests as state_requests,
    service_values as state_service_values]
import ../../../src/chain/parameters

discard recordAccumulationSolicit(default(AccumulationEffects), default(ServicePreimageHash),
    RequestLength(3), default(Parameters), AccountSlot(0))
