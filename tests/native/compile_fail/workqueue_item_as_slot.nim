# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ready-report ordinals cannot select epoch-ring slots.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: WorkQueueSlot but got: ReadyItemIndex"}

import ../../../src/codec/state/workqueues as state_workqueues
let owner = default(ReadySnapshot)
discard readySlotCount(owner, ReadyItemIndex(0))
