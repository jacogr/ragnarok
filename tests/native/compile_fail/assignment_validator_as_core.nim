## A guarantor validator ordinal cannot silently become a core-sequence position.
import ../../../src/[state_availability, guarantees]
var owner: AvailabilitySnapshot
var index: GuarantorIndex
let value = availabilityAt(owner, index)
discard value
