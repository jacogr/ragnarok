# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge success or change read-only result state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "value"}

import ../../../src/codec/state/outputs as state_outputs
var parsed = default(OutputLogResult[int])
parsed.value = 0
