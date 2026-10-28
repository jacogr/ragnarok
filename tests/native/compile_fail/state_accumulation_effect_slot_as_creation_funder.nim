# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationNew(","[5] expected: ServiceIndex but got: AccountSlot"]}

## Creation funding uses distinct account and mode domains.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/accumulation_invocation as state_accumulation_invocation

discard recordAccumulationNew(default(AccumulationEffects), default(AccumulationNewService),
    default(Parameters), ServiceProbeLimit(1), AccountSlot(0), AccumulationFundingMode(0))
