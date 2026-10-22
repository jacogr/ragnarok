# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationValidators but got: PreparedCurrentAccumulationRecent", "early": ["prepareCurrentAccumulationActivity(", "[1] expected: PreparedCurrentAccumulationValidators but got: PreparedCurrentAccumulationRecent"]}

## Exact current validator ownership is required.
import ../../../src/state/[accumulation_current_activity, accumulation_activity, accumulation_current_recent]
discard prepareCurrentAccumulationActivity(default(PreparedCurrentAccumulationRecent), default(AccumulationActivityConfig))
