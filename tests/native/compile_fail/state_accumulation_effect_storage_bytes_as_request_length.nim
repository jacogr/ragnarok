# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "RequestLength", "early": ["effectRequestHistory(", "[3] expected: RequestLength but got: AccountStorageBytes"]}

## Reject substitution of a different semantic domain at the request-history read boundary.

import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
discard effectRequestHistory(default(AccumulationEffectContext), default(ServicePreimageHash),
    AccountStorageBytes(3))
