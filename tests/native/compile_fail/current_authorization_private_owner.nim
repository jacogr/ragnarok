# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Current pool proof representation stays private.
import ../../../src/state/[accumulation_current_authorization, accumulation_authorization,
    accumulation_current_preimages]
let refused = prepareCurrentAccumulationAuthorization(default(PreparedCurrentAccumulationPreimages),
    default(AccumulationAuthorizationLimits))
discard default(PreparedCurrentAccumulationAuthorization).data
