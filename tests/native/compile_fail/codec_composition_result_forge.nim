# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot forge or retag successful composition results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/codec/state_composition as codec_state_composition
discard StateCompositionResult[StateSnapshot](status: StateCompositionError.None,
    completed: default(StateSnapshot))
