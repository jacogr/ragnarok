# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot forge or retag successful composition results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "value"}

import ../../../src/codec/state_composition
var parsed = default(StateCompositionResult[StateSnapshot])
parsed.value = default(StateSnapshot)
