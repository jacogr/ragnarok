# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting immutable initial accumulation ownership and gas domains.
## Its top-level access must fail semantic compilation rather than expose or forge validated values.

# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: Gas"}

import ../../../src/state/accumulation/round as accumulation_round
import ../../../src/codec/bounded
discard AccumulationRoundConfig(blockGas: ByteLimit(10)) # Byte ceilings are not protocol gas.
