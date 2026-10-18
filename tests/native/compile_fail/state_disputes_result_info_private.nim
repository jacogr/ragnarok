# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot access or forge private chapter-5 results or retained storage.
import ../../../src/codec/[state_disputes, state_trie]
let value = default(DisputeStateResult[DisputeStateInfo])
discard value.completed
