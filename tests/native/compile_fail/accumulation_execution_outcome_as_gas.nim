# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "InvocationServiceIndex", "early": ["executionGasAt(", "[2] expected: InvocationServiceIndex but got: AccumulationProvisionSourceIndex"]}

## Refuse access or substitution across the admitted execution certificate boundary.

import ../../../src/state/[accumulation_execution, accumulation_provisions]
var plan: CompletedBlockAccumulation
discard executionGasAt(plan, AccumulationProvisionSourceIndex(0))
