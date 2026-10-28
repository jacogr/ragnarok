# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationFundingMode","early":["recordAccumulationNew(","[6] expected: AccumulationFundingMode but got: AccountBalance"]}

## Creation funding uses distinct account and mode domains.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/accumulation_invocation as state_accumulation_invocation

discard recordAccumulationNew(default(AccumulationEffects), default(AccumulationNewService),
    default(Parameters), ServiceProbeLimit(1), ServiceIndex(42), AccountBalance(0))
