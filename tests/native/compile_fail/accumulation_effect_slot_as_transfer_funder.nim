# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["prepareAccumulationTransfer(","[7] expected: ServiceIndex but got: AccountSlot"]}

## Deferred funding uses distinct account and mode domains.
import ../../../src/state/accumulation_effects
import ../../../src/codec/[composite, state_accounts, c2_records]
import ../../../src/chain/parameters
import ../../../src/pvm/gas

discard prepareAccumulationTransfer(default(AccumulationEffects), AccumulationTransferDestination(
    99), TransferBalance(5), Gas(9), default(TransferMemo), default(Parameters), AccountSlot(0),
        AccumulationFundingMode(0))
