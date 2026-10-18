# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-14/15 result/owner storage.
import ../../../src/codec/[state_workqueues, state_trie]
var value = default(WorkQueueResult[WorkQueueInfo])
value.status = WorkQueueError.None
