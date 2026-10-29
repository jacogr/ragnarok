# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-12 results or owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "value"}

import ../../../src/codec/state/[privileges as state_privileges, trie as state_trie]
var value = default(PrivilegeResult[PrivilegeInfo])
value.value = default(PrivilegeInfo)
