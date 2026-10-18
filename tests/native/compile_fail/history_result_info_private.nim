# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-3 results, owners or peak alternatives.
import ../../../src/codec/[state_history, state_trie]
let value = default(HistoryResult[HistoryInfo])
discard value.completed
