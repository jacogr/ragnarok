# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationPreimages", "early": ["prepareAccumulationAuthorization(", "[1] expected: PreparedAccumulationPreimages but got: StateStoreSnapshot"]}

## Detached credentials or a complete state cannot replace the authenticated preimage candidate.

import ../../../src/state/accumulation/authorization as accumulation_authorization
import ../../../src/state/store
var source: StateStoreSnapshot
var limits: AccumulationAuthorizationLimits
discard prepareAccumulationAuthorization(source, limits)
