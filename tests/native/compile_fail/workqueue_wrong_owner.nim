## Accumulated history cannot substitute for a ready-report owner.
import ../../../src/state_workqueues
let owner = default(AccumulatedSnapshot)
discard readySlotCount(owner, WorkQueueSlot(0))
