# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationFundingMode","early":["prepareAccumulationTransfer(","[8] expected: AccumulationFundingMode but got: AccountBalance"]}

## Deferred funding uses distinct account and mode domains.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/chain/parameters as chain_parameters
import ../../../src/pvm/gas as pvm_gas

discard prepareAccumulationTransfer(default(AccumulationEffects), AccumulationTransferDestination(
    99), TransferBalance(5), Gas(9), default(TransferMemo), default(Parameters), ServiceIndex(42),
        AccountBalance(0))
