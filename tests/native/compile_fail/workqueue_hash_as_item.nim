# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A set-member ordinal cannot select a ready report.
import ../../../src/codec/state_workqueues
let owner = default(ReadySnapshot)
discard readyItemAt(owner, WorkQueueSlot(0), WorkQueueHashIndex(0))
