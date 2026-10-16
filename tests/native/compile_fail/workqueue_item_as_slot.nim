## Ready-report ordinals cannot select epoch-ring slots.
import ../../../src/state_workqueues
let owner = default(ReadySnapshot)
discard readySlotCount(owner, ReadyItemIndex(0))
