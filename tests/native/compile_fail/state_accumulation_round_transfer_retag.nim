# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Guarded completed-round ownership cannot be bypassed by direct field access.

import ../../../src/state/accumulation_round_transfers as state_accumulation_round_transfers
var result: AccumulationRoundTransferResult[PreparedRoundAccumulationTransfers]
result.status = AccumulationRoundTransferError.None
