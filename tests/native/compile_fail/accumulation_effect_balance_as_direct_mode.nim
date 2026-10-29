# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationFundingMode","early":["recordAccumulationDirectTransfer(","[5] expected: AccumulationFundingMode but got: AccountBalance"]}

## Direct funding uses distinct account and mode domains.
import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
import ../../../src/codec/state/accounts as state_accounts
import ../../../src/codec/c2_records
import ../../../src/chain/parameters

discard recordAccumulationDirectTransfer(default(AccumulationEffects), ServiceIndex(42),
    AccumulationTransferDestination(99), TransferBalance(5), AccountBalance(0), default(Parameters))
