## Safe callers cannot bypass guarded assurance results through status.
import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
value.status = AssuranceError.None
