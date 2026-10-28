# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler-rejection fixture protecting private prepared operands and bound source provenance.
## Its top-level field access must fail semantic compilation rather than expose mutable storage.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/accumulation_operands as state_accumulation_operands
let owner = default(AccumulationOperandResult[BlockAccumulationOperands])
discard owner.completed # Private result/owner data cannot be read or forged.
