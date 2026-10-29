# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationRecent but got: PreparedCurrentAccumulationReady", "early": ["prepareCurrentAccumulationValidators(", "[1] expected: PreparedCurrentAccumulationRecent but got: PreparedCurrentAccumulationReady"]}

## Exact current recent-history ownership is required.
import ../../../src/state/accumulation/current/validators as accumulation_current_validators
import ../../../src/state/accumulation/validators as accumulation_validators
import ../../../src/state/accumulation/current/ready as accumulation_current_ready
discard prepareCurrentAccumulationValidators(default(PreparedCurrentAccumulationReady), default(AccumulationValidatorsConfig))
