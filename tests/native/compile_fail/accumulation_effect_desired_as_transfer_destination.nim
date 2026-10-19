# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationTransferDestination", "early": ["prepareAccumulationTransfer(", "[2] expected: AccumulationTransferDestination but got: AccumulationDesiredService"]}

## Reject a service creation proposal used as a transfer destination.

import ../../../src/state/accumulation_effects
import ../../../src/codec/[state_accounts, c2_records]
import ../../../src/chain/parameters
discard prepareAccumulationTransfer(default(AccumulationEffects), AccumulationDesiredService(99),
  TransferBalance(0), Gas(0), default(TransferMemo), default(Parameters))
