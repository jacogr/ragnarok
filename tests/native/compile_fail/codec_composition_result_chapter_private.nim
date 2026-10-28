# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete composition payloads remain private behind the success accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_trie as codec_state_trie
let parsed = default(StateCompositionResult[StateChapterSnapshot])
discard parsed.completed
