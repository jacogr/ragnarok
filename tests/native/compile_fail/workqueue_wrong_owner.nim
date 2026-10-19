# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Accumulated history cannot substitute for a ready-report owner.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "[1] expected: ReadySnapshot but got: AccumulatedSnapshot"}

import ../../../src/codec/state_workqueues
let owner = default(AccumulatedSnapshot)
discard readySlotCount(owner, WorkQueueSlot(0))
