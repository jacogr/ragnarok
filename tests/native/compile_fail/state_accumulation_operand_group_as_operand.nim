# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler-rejection fixture for distinct prefix, service identity/group and operand ordinal roles.
## Its top-level call supplies the wrong nominal domain; a successful build is a test failure.

# @@Verification={"group": "nominal", "expected": "[3] expected: ServiceOperandIndex but got: OperandServiceIndex", "early": ["serviceOperandAt(", "[3] expected: ServiceOperandIndex but got: OperandServiceIndex"]}

import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/codec/composite as codec_composite
discard serviceOperandAt(default(PreparedAccumulationOperands), OperandServiceIndex(0),
    OperandServiceIndex(0))
