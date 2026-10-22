# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationNew(","[5] expected: ServiceIndex but got: AccountSlot"]}

## Creation funding uses distinct account and mode domains.
import ../../../src/state/accumulation_effects
import ../../../src/codec/[composite, state_accounts]
import ../../../src/chain/parameters
import ../../../src/state/accumulation_invocation

discard recordAccumulationNew(default(AccumulationEffects), default(AccumulationNewService),
    default(Parameters), ServiceProbeLimit(1), AccountSlot(0), AccumulationFundingMode(0))
