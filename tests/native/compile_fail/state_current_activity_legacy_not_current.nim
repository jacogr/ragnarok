# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationValidators but got: PreparedAccumulationValidators", "early": ["prepareCurrentAccumulationActivity(", "[1] expected: PreparedCurrentAccumulationValidators but got: PreparedAccumulationValidators"]}

## Exact current validator ownership is required.
import ../../../src/state/accumulation_current_activity as state_accumulation_current_activity
import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/accumulation_validators as state_accumulation_validators
discard prepareCurrentAccumulationActivity(default(PreparedAccumulationValidators), default(AccumulationActivityConfig))
