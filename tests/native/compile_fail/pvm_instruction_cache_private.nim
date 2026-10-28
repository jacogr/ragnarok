# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only the owning invocation can select a cached decode; external callers cannot inject operands or reuse a foreign program memo.
# @@Verification={"group": "privacy", "expected": "cachedInstruction"}
import ../../../src/pvm/step as pvm_step
discard pvm_step.cachedInstruction
