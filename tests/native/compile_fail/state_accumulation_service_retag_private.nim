# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private service-context storage and nominal argument domains.
## Its top-level access or call must fail semantic compilation rather than forge validated context.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
let owner = default(AccumulationServiceResult[PreparedAccumulationService])
discard owner.status # Private storage cannot be forged or modified.
