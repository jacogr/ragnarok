# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or fabricate component results or retained roster storage.
import ../../../src/codec/[state_safrole, state_trie]
let value = default(StateComponentResult[StateEntry])
discard value.completed
