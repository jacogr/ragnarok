# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["prepareRoundAccumulationTransfers(", "[1] expected: CompletedBlockAccumulation but got: PreparedAccumulationBatch"]}

## A pure common-source batch cannot replace admitted-round execution and verified actual gas provenance.

import ../../../src/state/accumulation_round_transfers as state_accumulation_round_transfers
import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_transfers as state_accumulation_transfers
let batch = default(PreparedAccumulationBatch)
discard prepareRoundAccumulationTransfers(batch, default(AccumulationTransferCollectionLimits))
