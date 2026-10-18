# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete composition payloads remain private behind the success accessor.
import ../../../src/codec/[state_composition, state_trie]
let parsed = default(StateCompositionResult[StateSnapshot])
discard parsed.completed
