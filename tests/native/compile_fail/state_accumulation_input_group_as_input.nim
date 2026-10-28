# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private invocation storage and nominal indexing.
## Its top-level access/call must fail compilation rather than expose or forge validated values.

# @@Verification={"group": "nominal", "expected": "[3] expected: InvocationInputIndex but got: OperandServiceIndex", "early": ["invocationInputAt(", "[3] expected: InvocationInputIndex but got: OperandServiceIndex"]}

import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/codec/composite as codec_composite
discard invocationInputAt(default(PreparedAccumulationInputs), InvocationServiceIndex(0),
    OperandServiceIndex(0))
