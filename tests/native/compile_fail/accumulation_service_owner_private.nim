# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private service-context storage and nominal argument domains.
## Its top-level access or call must fail semantic compilation rather than forge validated context.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/accumulation/[service as accumulation_service,
    round as accumulation_round, inputs as accumulation_inputs]
import ../../../src/codec/[bounded, composite]
let owner = default(PreparedAccumulationService)
discard owner.data # Private storage cannot be forged or modified.
