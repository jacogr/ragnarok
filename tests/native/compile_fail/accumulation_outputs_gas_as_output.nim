# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "OutputLogIndex", "early": ["outputAt(", "[2] expected: OutputLogIndex but got: InvocationServiceIndex"]}

## Refuse access or substitution across the admitted output projection boundary.

import ../../../src/state/[accumulation_outputs, accumulation_inputs]
var plan: PreparedAccumulationOutputs
discard outputAt(plan, InvocationServiceIndex(0))
