# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationRecent but got: PreparedCurrentAccumulationReady"}

## Exact current recent-history ownership is required.
import ../../../src/state/[accumulation_current_validators, accumulation_validators, accumulation_current_ready]
discard prepareCurrentAccumulationValidators(default(PreparedCurrentAccumulationReady), default(AccumulationValidatorsConfig))
