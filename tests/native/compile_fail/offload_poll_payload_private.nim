# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot inspect private completion state or payload.
import ../../../src/quic/offload
let polled = default(OffloadPollResult)
discard polled.completed
