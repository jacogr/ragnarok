# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "RequestLength", "early": ["recordAccumulationSolicit(", "[3] expected: RequestLength but got: RequestSlot"]}

## Reject a different semantic hash or E4 domain at the solicitation mutation boundary.

import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    requests as state_requests]
import ../../../src/chain/parameters
discard recordAccumulationSolicit(default(AccumulationEffects), default(ServicePreimageHash),
    RequestSlot(3), default(Parameters))
