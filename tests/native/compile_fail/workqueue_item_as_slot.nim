# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ready-report ordinals cannot select epoch-ring slots.
import ../../../src/codec/state_workqueues
let owner = default(ReadySnapshot)
discard readySlotCount(owner, ReadyItemIndex(0))
