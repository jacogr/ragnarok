## Callers cannot access or retag private C.2 result/variant state.
import ../../../src/codec/[c2_records, composite]
var value = default(RecordResult[AvailabilityRead])
discard value.completed
