## Absolute timeslots cannot substitute for parent service IDs.
import ../../../src/codec/state_accounts
let metadata = ServiceMetadata(parent: AccountSlot(1))
discard metadata
