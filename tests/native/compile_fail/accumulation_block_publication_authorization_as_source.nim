# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationConsensus", "early": ["publishAccumulationState(", "[2] expected: PreparedAccumulationConsensus but got: PreparedAccumulationAuthorization"]}

## Raw maps and earlier report/accumulation prefixes cannot authorize composed candidate publication.

import ../../../src/state/[accumulation_block_publication, store, accumulation_authorization]
var state: StateStore
var source: PreparedAccumulationAuthorization
discard publishAccumulationState(state, source)
