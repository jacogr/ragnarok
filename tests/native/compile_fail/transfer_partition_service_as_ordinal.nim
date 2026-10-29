# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"TransferPartitionIndex","early":["partitionTransferAt(","[3] expected: TransferPartitionIndex but got: ServiceIndex"]}

## Partition ownership, selected results and nominal units cannot be substituted.
import ../../../src/state/accumulation/transfer_partition as accumulation_transfer_partition
import ../../../src/codec/state/accounts as state_accounts

discard partitionTransferAt(default(PreparedTransferPartition), TransferPartitionKind.Accepted,
    ServiceIndex(1))
