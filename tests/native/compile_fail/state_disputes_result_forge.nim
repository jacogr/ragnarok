# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot access or forge private chapter-5 results or retained storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/codec/[state_disputes, state_trie]
discard DisputeStateResult[DisputeStateInfo](status: DisputeStateError.None)
