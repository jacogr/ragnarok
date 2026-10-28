# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private invocation storage and nominal indexing.
## Its top-level access/call must fail compilation rather than expose or forge validated values.

# @@Verification={"group": "nominal", "expected": "[2] expected: InvocationServiceIndex but got: ServiceIndex", "early": ["invocationServiceAt(", "[2] expected: InvocationServiceIndex but got: ServiceIndex"]}

import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/codec/composite as codec_composite
discard invocationServiceAt(default(PreparedAccumulationInputs), ServiceIndex(0))
