# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationProvisionSourceIndex", "early": ["batchOutcomeAt(", "[2] expected: AccumulationProvisionSourceIndex but got: InvocationServiceIndex"]}

## A service-group position cannot substitute a plan-owned execution ordinal.

import ../../../src/state/accumulation/[batch as accumulation_batch, inputs as accumulation_inputs]
var plan: PreparedAccumulationBatch
discard batchOutcomeAt(plan, InvocationServiceIndex(0))
