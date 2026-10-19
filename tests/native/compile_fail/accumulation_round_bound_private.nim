# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting immutable initial accumulation ownership and gas domains.
## Its top-level access must fail semantic compilation rather than expose or forge validated values.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/accumulation_round
import ../../../src/codec/bounded
let owner = default(BlockAccumulationRound)
discard owner.data # Private storage cannot be forged or modified.
