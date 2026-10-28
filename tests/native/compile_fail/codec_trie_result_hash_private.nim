# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or fabricate completed trie commitments or child
## hashes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
let value = default(StateTrieResult[StateNodeHash])
discard value.completed
