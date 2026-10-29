# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bare completed execution cannot replace retained authenticated assurance provenance.

# @@Verification={"group": "nominal", "expected": "ExecutedAssuredAccumulation", "early": ["composeAssuredState(", "[1] expected: ExecutedAssuredAccumulation but got: CompletedBlockAccumulation"]}

import ../../../src/state/assured/composition as assured_composition
import ../../../src/state/accumulation/execution as accumulation_execution
discard composeAssuredState(default(CompletedBlockAccumulation), AssuredCompositionConfig())
