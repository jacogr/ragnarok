# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationAuthorization but got: PreparedAccumulationAuthorization", "early": ["prepareCurrentAccumulationConsensus(", "[1] expected: PreparedCurrentAccumulationAuthorization but got: PreparedAccumulationAuthorization"]}

## Exact current pool-advancement ownership is required.
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/accumulation_authorization as state_accumulation_authorization
discard prepareCurrentAccumulationConsensus(default(PreparedAccumulationAuthorization), default(AccumulationConsensusLimits))
