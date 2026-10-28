# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationAuthorization", "early": ["prepareAccumulationConsensus(", "[1] expected: PreparedAccumulationAuthorization but got: BlockTransitionResult"]}

## Detached stages, assignments and complete maps cannot replace the authenticated accumulation source.

import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/block_transition as state_block_transition
var source: BlockTransitionResult
var limits: AccumulationConsensusLimits
discard prepareAccumulationConsensus(source, limits)
