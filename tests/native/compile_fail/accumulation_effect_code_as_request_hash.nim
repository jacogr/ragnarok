# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ServicePreimageHash", "early": ["effectRequestHistory(", "[2] expected: ServicePreimageHash but got: CodeHash"]}

## Reject substitution of a different semantic domain at the request-history read boundary.

import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    requests as state_requests]
discard effectRequestHistory(default(AccumulationEffectContext), default(CodeHash), RequestLength(3))
