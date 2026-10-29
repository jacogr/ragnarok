# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current pool proof representation stays private.
import ../../../src/state/accumulation/current/authorization as accumulation_current_authorization
import ../../../src/state/accumulation/authorization as accumulation_authorization
import ../../../src/state/accumulation/current/preimages as accumulation_current_preimages
let refused = prepareCurrentAccumulationAuthorization(default(PreparedCurrentAccumulationPreimages),
    default(AccumulationAuthorizationLimits))
discard refused.completed
