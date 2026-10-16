## Absolute timeslots cannot substitute for parent service IDs.
import ../../../src/state_accounts
let metadata = ServiceMetadata(parent: AccountSlot(1))
discard metadata
