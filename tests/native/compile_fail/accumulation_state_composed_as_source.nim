# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedFinalAccumulation", "early": ["applyAccumulationState(", "[2] expected: PreparedFinalAccumulation but got: PreparedAccumulationConsensus"]}

## Only the immutable finalized execution successor authorizes state application.

import ../../../src/state/accumulation/[state as accumulation_state,
    completion as accumulation_completion]
import ../../../src/state/store
import ../../../src/state/accumulation/consensus as accumulation_consensus
var target: StateStore
var source: PreparedAccumulationConsensus
discard applyAccumulationState(target, source, default(AccumulationCompositionLimits))
