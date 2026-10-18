# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A complete trie root cannot silently masquerade as an internal node hash.
import ../../../src/codec/[state_trie, state_layout]
let root = default(StateRoot)
let node = encodeStateBranch(root, root)
discard node
