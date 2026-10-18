# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-12 results or owner storage.
import ../../../src/codec/[state_privileges, state_trie]
let value = default(PrivilegeResult[ServiceIndex])
discard value.completed
