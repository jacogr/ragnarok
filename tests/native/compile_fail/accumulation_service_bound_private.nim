# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private service-context storage and nominal argument domains.
## Its top-level access or call must fail semantic compilation rather than forge validated context.

import ../../../src/state/[accumulation_service, accumulation_round, accumulation_inputs]
import ../../../src/codec/[bounded, composite]
let owner = default(BlockAccumulationService)
discard owner.data # Private storage cannot be forged or modified.
