# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-13 result/owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state/[statistics as state_statistics, trie as state_trie]
let value = default(ActivityResult[array[8, uint64]])
discard value.completed
