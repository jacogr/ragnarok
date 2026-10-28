# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationAuthorization", "early": ["prepareAccumulationConsensus(", "[1] expected: PreparedAccumulationAuthorization but got: StateStoreSnapshot"]}

## Detached stages, assignments and complete maps cannot replace the authenticated accumulation source.

import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/store as state_store
var source: StateStoreSnapshot
var limits: AccumulationConsensusLimits
discard prepareAccumulationConsensus(source, limits)
