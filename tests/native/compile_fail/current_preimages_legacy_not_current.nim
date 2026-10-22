# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationActivity but got: PreparedAccumulationActivity", "early": ["prepareCurrentAccumulationPreimages(", "[1] expected: PreparedCurrentAccumulationActivity but got: PreparedAccumulationActivity"]}

## Exact current C13 activity ownership is required.
import ../../../src/state/[accumulation_current_preimages, accumulation_preimages, accumulation_activity]
discard prepareCurrentAccumulationPreimages(default(PreparedAccumulationActivity), default(AccumulationPreimageLimits))
