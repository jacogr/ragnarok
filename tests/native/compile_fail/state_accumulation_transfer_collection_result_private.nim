# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Collection storage and semantic ordinals cannot bypass the guarded public API.

import ../../../src/state/accumulation_transfers as state_accumulation_transfers
var result: AccumulationTransferCollectionResult[PreparedAccumulationTransfers]
discard result.completed
