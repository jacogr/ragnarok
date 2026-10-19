# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-14/15 result/owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/codec/[state_workqueues, state_trie]
discard WorkQueueResult[WorkQueueInfo](status: WorkQueueError.None)
