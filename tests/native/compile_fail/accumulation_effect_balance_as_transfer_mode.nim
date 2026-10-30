# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationFundingMode","early":["prepareAccumulationTransfer(","[8] expected: AccumulationFundingMode but got: AccountBalance"]}

## Deferred funding uses distinct account and mode domains.
import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
import ../../../src/codec/state/accounts as state_accounts
import ../../../src/codec/c2_records
import ../../../src/chain/parameters
import ../../../src/pvm/gas/gas

discard prepareAccumulationTransfer(default(AccumulationEffects), AccumulationTransferDestination(
    99), TransferBalance(5), Gas(9), default(TransferMemo), default(Parameters), ServiceIndex(42),
        AccountBalance(0))
