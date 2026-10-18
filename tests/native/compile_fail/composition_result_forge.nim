# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot forge or retag successful composition results.
import ../../../src/codec/state_composition
discard StateCompositionResult[StateSnapshot](status: StateCompositionError.None,
    completed: default(StateSnapshot))
