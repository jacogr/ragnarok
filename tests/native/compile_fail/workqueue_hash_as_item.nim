# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A set-member ordinal cannot select a ready report.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[3] expected: ReadyItemIndex but got: WorkQueueHashIndex"}

import ../../../src/codec/state/workqueues as state_workqueues
let owner = default(ReadySnapshot)
discard readyItemAt(owner, WorkQueueSlot(0), WorkQueueHashIndex(0))
