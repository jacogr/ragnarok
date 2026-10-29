# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationPreimages but got: PreparedCurrentAccumulationActivity", "early": ["prepareCurrentAccumulationAuthorization(", "[1] expected: PreparedCurrentAccumulationPreimages but got: PreparedCurrentAccumulationActivity"]}

## Exact current fulfilled-preimage ownership is required.
import ../../../src/state/accumulation/current/authorization as accumulation_current_authorization
import ../../../src/state/accumulation/authorization as accumulation_authorization
import ../../../src/state/accumulation/current/activity as accumulation_current_activity
discard prepareCurrentAccumulationAuthorization(default(PreparedCurrentAccumulationActivity),
    default(AccumulationAuthorizationLimits))
