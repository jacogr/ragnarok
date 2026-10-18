# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-13 result/owner storage.
import ../../../src/codec/[state_statistics, state_trie]
let value = default(ActivityResult[uint64])
discard value.completed
