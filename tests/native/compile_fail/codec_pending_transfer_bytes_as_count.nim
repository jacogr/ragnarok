# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"got: ByteLimit but wanted: ElementLimit"}

## Pending ownership, selected reasons and nominal budget/ordinal units remain private or distinct.
import ../../../src/state/accumulation_pending_transfers as state_accumulation_pending_transfers
import ../../../src/codec/bounded as codec_bounded

discard PendingTransferLimits(transfers: ByteLimit(1))
