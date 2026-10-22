# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"PendingTransferIndex","early":["pendingTransferAt(","[2] expected: PendingTransferIndex but got: TransferPartitionIndex"]}

## Pending ownership, selected reasons and nominal budget/ordinal units remain private or distinct.
import ../../../src/state/[accumulation_pending_transfers, accumulation_transfer_partition]

discard pendingTransferAt(default(PreparedPendingTransfers), TransferPartitionIndex(0))
