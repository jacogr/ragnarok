# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A complete trie root cannot silently masquerade as an internal node hash.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "StateRoot"}

import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
let root = default(StateRoot)
let node = encodeStateBranch(root, root)
discard node
