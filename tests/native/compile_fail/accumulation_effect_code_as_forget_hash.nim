# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ServicePreimageHash", "early": ["recordAccumulationForget(", "[2] expected: ServicePreimageHash but got: CodeHash"]}

## Reject substitution of a different semantic hash or E4 domain at the forget mutation boundary.

import ../../../src/state/accumulation_effects
import ../../../src/codec/[state_accounts, state_service_values, state_requests]
import ../../../src/chain/parameters
discard recordAccumulationForget(default(AccumulationEffects), default(CodeHash), RequestLength(3),
    default(Parameters))
