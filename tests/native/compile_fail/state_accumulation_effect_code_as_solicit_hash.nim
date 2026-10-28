# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ServicePreimageHash", "early": ["recordAccumulationSolicit(", "[2] expected: ServicePreimageHash but got: CodeHash"]}

## Reject a different semantic hash or E4 domain at the solicitation mutation boundary.

import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/chain/parameters as chain_parameters
discard recordAccumulationSolicit(default(AccumulationEffects), default(CodeHash), RequestLength(3),
    default(Parameters))
