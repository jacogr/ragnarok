## Availability segment roots cannot occupy the erasure commitment role.
import ../../../src/[c2_records, work_report]
let value = AvailabilitySpec(erasureRoot: SegmentRoot())
discard value
