# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture preventing accidental bound/pure service API interchange.
## Block-bound provenance must use its dedicated adapter rather than an implicit representation conversion.

# @@Verification={"group": "nominal", "expected": "PreparedAccumulationService", "early": ["finishUninvokedAccumulation(", "[1] expected: PreparedAccumulationService but got: BlockAccumulationService"]}

import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_service as state_accumulation_service
discard finishUninvokedAccumulation(default(BlockAccumulationService))
