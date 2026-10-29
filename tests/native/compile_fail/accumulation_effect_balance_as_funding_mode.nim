# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationFundingMode","early":["recordAccumulationNew(","[6] expected: AccumulationFundingMode but got: AccountBalance"]}

## Creation funding uses distinct account and mode domains.
import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
import ../../../src/codec/state/accounts as state_accounts
import ../../../src/chain/parameters
import ../../../src/state/accumulation/invocation as accumulation_invocation

discard recordAccumulationNew(default(AccumulationEffects), default(AccumulationNewService),
    default(Parameters), ServiceProbeLimit(1), ServiceIndex(42), AccountBalance(0))
