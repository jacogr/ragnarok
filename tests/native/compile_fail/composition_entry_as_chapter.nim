# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw key/value entries cannot forge validated immutable chapter captures.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: StateEntry but wanted: StateChapterSnapshot"}

import ../../../src/codec/state/[composition as state_composition, trie as state_trie]
let part: StateChapterSnapshot = default(StateEntry)
discard part
