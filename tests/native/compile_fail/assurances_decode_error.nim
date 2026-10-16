## Safe callers cannot bypass guarded assurance results through error.
import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
value.error = AssuranceError.None
