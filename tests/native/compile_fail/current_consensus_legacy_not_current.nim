# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationAuthorization but got: PreparedAccumulationAuthorization", "early": ["prepareCurrentAccumulationConsensus(", "[1] expected: PreparedCurrentAccumulationAuthorization but got: PreparedAccumulationAuthorization"]}

## Exact current pool-advancement ownership is required.
import ../../../src/state/accumulation/current/consensus as accumulation_current_consensus
import ../../../src/state/accumulation/[consensus as accumulation_consensus,
    authorization as accumulation_authorization]
discard prepareCurrentAccumulationConsensus(default(PreparedAccumulationAuthorization), default(AccumulationConsensusLimits))
