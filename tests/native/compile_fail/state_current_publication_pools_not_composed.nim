# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationConsensus but got: PreparedCurrentAccumulationAuthorization", "early": ["publishCurrentAccumulationState(", "[2] expected: PreparedCurrentAccumulationConsensus but got: PreparedCurrentAccumulationAuthorization"]}

## Exact current consensus composition is required before publication.
import ../../../src/state/accumulation_current_publication as state_accumulation_current_publication
import ../../../src/state/accumulation_current_authorization as state_accumulation_current_authorization
import ../../../src/state/store as state_store
var state = default(StateStore)
discard publishCurrentAccumulationState(state, default(PreparedCurrentAccumulationAuthorization))
