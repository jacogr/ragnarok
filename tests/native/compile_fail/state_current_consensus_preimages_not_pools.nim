# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationAuthorization but got: PreparedCurrentAccumulationPreimages", "early": ["prepareCurrentAccumulationConsensus(", "[1] expected: PreparedCurrentAccumulationAuthorization but got: PreparedCurrentAccumulationPreimages"]}

## Exact current pool-advancement ownership is required.
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/accumulation_current_preimages as state_accumulation_current_preimages
discard prepareCurrentAccumulationConsensus(default(PreparedCurrentAccumulationPreimages), default(AccumulationConsensusLimits))
