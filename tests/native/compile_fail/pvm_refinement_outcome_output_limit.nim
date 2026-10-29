# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Guest host-copy budgets cannot silently replace normalized return-output budgets.

# @@Verification={"group": "nominal", "expected": "got: MemoryByteLimit but wanted: OutputByteLimit"}

import ../../../src/state/refinement/outcome as refinement_outcome
import ../../../src/pvm/machine
discard RefinementInvocationLimits(output: MemoryByteLimit(0))
