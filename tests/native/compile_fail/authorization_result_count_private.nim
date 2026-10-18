# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or fabricate authorization results or retained nested rows.
import ../../../src/codec/[state_authorization, state_trie]
let value = default(AuthorizationResult[tuple[count: uint64, prefix: int]])
discard value.completed
