# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"Gas","early":["prepareInitialPendingTransfers(","[2] expected: Gas but got: TransferBalance"]}

## Pending ownership, selected reasons and nominal budget/ordinal units remain private or distinct.
import ../../../src/state/accumulation/[pending_transfers as accumulation_pending_transfers,
    transfers as accumulation_transfers]
import ../../../src/codec/c2_records

discard prepareInitialPendingTransfers(default(PreparedAccumulationTransfers), TransferBalance(1),
    default(PendingTransferLimits))
