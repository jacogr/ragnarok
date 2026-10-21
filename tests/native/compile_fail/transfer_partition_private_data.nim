# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"data"}

## Partition ownership, selected results and nominal units cannot be substituted.
import ../../../src/state/accumulation_transfer_partition

discard default(PreparedTransferPartition).data
