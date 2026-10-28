# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationEjectTarget", "early": ["recordAccumulationEject(", "[2] expected: AccumulationEjectTarget but got: AccumulationTransferDestination"]}

## Reject a transfer destination reused as an eject target without an explicit domain conversion.

import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/chain/parameters as chain_parameters
discard recordAccumulationEject(default(AccumulationEffects), AccumulationTransferDestination(99),
  default(Parameters))
