## Guarantee evaluation slots cannot substitute for assignment registration timestamps.
import ../../../src/codec/[state_availability, guarantees]
let slot = default(GuaranteeSlot)
discard presentAssignment(default(Guarantee), slot)
