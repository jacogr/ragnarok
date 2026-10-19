# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedBlockActivity", "early": ["prepareAccumulationPublication(", "[1] expected: PreparedBlockActivity but got: ActivityState"]}

## Raw metrics cannot replace a complete source-bound activity certificate.

import ../../../src/state/accumulation_publication
import ../../../src/codec/state_statistics
var source: ActivityState
var config: AccumulationPublicationConfig
discard prepareAccumulationPublication(source, config)
