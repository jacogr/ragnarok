# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or fabricate completed trie commitments or child
## hashes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "error"}

import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
var value = default(StateTrieResult[StateTrieCommitment])
value.error = StateTrieError.None
