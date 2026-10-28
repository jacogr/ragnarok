# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public trie handles/results must not expose mutable owners or unguarded alternatives.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/storage/full_state_trie as storage_full_state_trie

let hidden = default(TrieResult[FullStateTrie])
discard hidden.completed
