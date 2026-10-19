# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationPublication", "early": ["publishAccumulation(", "[1] expected: PreparedAccumulationPublication but got: PreparedBlockActivity"]}

## Complete activity alone cannot substitute for the coordinated account/history/statistics batch.

import ../../../src/state/[accumulation_publication, block_activity]
var source: PreparedBlockActivity
discard publishAccumulation(source)
