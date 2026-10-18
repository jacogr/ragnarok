# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw key/value entries cannot forge validated immutable chapter captures.
import ../../../src/codec/[state_composition, state_trie]
let part: StateChapterSnapshot = default(StateEntry)
discard part
