# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationFundingMode","early":["recordAccumulationNew(","[6] expected: AccumulationFundingMode but got: AccountBalance"]}

## Creation funding uses distinct account and mode domains.
import ../../../src/state/accumulation_effects
import ../../../src/codec/[composite, state_accounts]
import ../../../src/chain/parameters
import ../../../src/state/accumulation_invocation

discard recordAccumulationNew(default(AccumulationEffects), default(AccumulationNewService),
    default(Parameters), ServiceProbeLimit(1), ServiceIndex(42), AccountBalance(0))
