# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"partitionReason"}

## Pending ownership, selected reasons and nominal budget/ordinal units remain private or distinct.
import ../../../src/state/accumulation/[pending_transfers as accumulation_pending_transfers,
    transfers as accumulation_transfers]
import ../../../src/codec/state/accounts as state_accounts

let candidate = prepareInitialPendingTransfers(default(PreparedAccumulationTransfers), Gas(0),
    default(PendingTransferLimits))
discard candidate.partitionReason
