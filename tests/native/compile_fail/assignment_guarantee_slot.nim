## Guarantee evaluation time cannot silently become the assignment registration time.
import ../../../src/[state_availability, guarantees]
var slot: GuaranteeSlot
let assignment = AvailabilityAssignment(present: true, registered: slot)
discard assignment
