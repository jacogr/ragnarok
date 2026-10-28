# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bare completed execution cannot replace retained authenticated assurance provenance.

# @@Verification={"group": "nominal", "expected": "ExecutedAssuredAccumulation", "early": ["composeAssuredState(", "[1] expected: ExecutedAssuredAccumulation but got: CompletedBlockAccumulation"]}

import ../../../src/state/assured_composition as state_assured_composition
import ../../../src/state/accumulation_execution as state_accumulation_execution
discard composeAssuredState(default(CompletedBlockAccumulation), AssuredCompositionConfig())
