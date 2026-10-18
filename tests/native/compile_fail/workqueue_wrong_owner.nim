# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Accumulated history cannot substitute for a ready-report owner.
import ../../../src/codec/state_workqueues
let owner = default(AccumulatedSnapshot)
discard readySlotCount(owner, WorkQueueSlot(0))
