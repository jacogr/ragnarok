# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationDirectTransfer(","[2] expected: ServiceIndex but got: AccountSlot"]}

## Direct funding uses distinct account and mode domains.
import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
import ../../../src/codec/state/accounts as state_accounts
import ../../../src/codec/c2_records
import ../../../src/chain/parameters

discard recordAccumulationDirectTransfer(default(AccumulationEffects), AccountSlot(0),
    AccumulationTransferDestination(99), TransferBalance(5), AccumulationFundingMode(0), default(Parameters))
