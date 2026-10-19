# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refuse access or substitution across the admitted output projection boundary.

import ../../../src/state/accumulation_outputs
var result: AccumulationOutputsResult[PreparedAccumulationOutputs]
discard result.status
