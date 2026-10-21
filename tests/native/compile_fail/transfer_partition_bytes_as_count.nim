# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"got: ByteLimit but wanted: ElementLimit"}

## Partition ownership, selected results and nominal units cannot be substituted.
import ../../../src/state/accumulation_transfer_partition
import ../../../src/codec/bounded

discard TransferPartitionLimits(transfers: ByteLimit(1))
