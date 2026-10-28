# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationValidators", "early": ["prepareAccumulationActivity(", "[1] expected: PreparedAccumulationValidators but got: CoreServiceActivityProjection"]}

## Detached statistics cannot construct a certified combined activity candidate.

import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/core_service_activity as state_core_service_activity
var source: CoreServiceActivityProjection
var config: AccumulationActivityConfig
discard prepareAccumulationActivity(source, config)
