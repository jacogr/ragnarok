# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"status"}

## Partition ownership, selected results and nominal units cannot be substituted.
import ../../../src/state/accumulation/transfer_partition as accumulation_transfer_partition

var candidate = default(TransferPartitionResult[int])
candidate.status = TransferPartitionError.None
