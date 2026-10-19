# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-12 results or owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/[state_privileges, state_trie]
let value = default(PrivilegeResult[AlwaysAccumulate])
discard value.completed
