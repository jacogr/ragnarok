# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Result success payloads cannot be read outside the guarded accessor.
import ../../../src/codec/[state_outputs, state_trie]
let parsed = default(OutputLogResult[int])
discard parsed.completed
