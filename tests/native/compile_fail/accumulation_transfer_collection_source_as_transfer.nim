# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CollectedTransferIndex", "early": ["collectedTransferAt(", "[2] expected: CollectedTransferIndex but got: AccumulationTransferSourceIndex"]}

## Collection storage and semantic ordinals cannot bypass the guarded public API.

import ../../../src/state/accumulation/transfers as accumulation_transfers
let plan = default(PreparedAccumulationTransfers)
discard collectedTransferAt(plan, AccumulationTransferSourceIndex(0))
