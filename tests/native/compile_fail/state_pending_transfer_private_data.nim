# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"data"}

## Pending ownership, selected reasons and nominal budget/ordinal units remain private or distinct.
import ../../../src/state/accumulation_pending_transfers as state_accumulation_pending_transfers

discard default(PreparedPendingTransfers).data
