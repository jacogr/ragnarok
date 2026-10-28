# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationActivity but got: PreparedCurrentAccumulationValidators", "early": ["prepareCurrentAccumulationPreimages(", "[1] expected: PreparedCurrentAccumulationActivity but got: PreparedCurrentAccumulationValidators"]}

## Exact current C13 activity ownership is required.
import ../../../src/state/accumulation_current_preimages as state_accumulation_current_preimages
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_current_validators as state_accumulation_current_validators
discard prepareCurrentAccumulationPreimages(default(PreparedCurrentAccumulationValidators), default(AccumulationPreimageLimits))
