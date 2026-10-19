# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["prepareRoundAccumulationTransfers(", "[1] expected: CompletedBlockAccumulation but got: PreparedAccumulationBatch"]}

## A pure common-source batch cannot replace admitted-round execution and verified actual gas provenance.

import ../../../src/state/[accumulation_round_transfers, accumulation_batch, accumulation_transfers]
let batch = default(PreparedAccumulationBatch)
discard prepareRoundAccumulationTransfers(batch, default(AccumulationTransferCollectionLimits))
