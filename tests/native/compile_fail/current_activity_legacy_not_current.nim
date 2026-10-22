# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationValidators but got: PreparedAccumulationValidators"}

## Exact current validator ownership is required.
import ../../../src/state/[accumulation_current_activity, accumulation_activity, accumulation_validators]
discard prepareCurrentAccumulationActivity(default(PreparedAccumulationValidators), default(AccumulationActivityConfig))
