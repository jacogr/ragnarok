## Safe callers cannot bypass guarded assurance results through byteConsumed.
import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
echo value.byteConsumed
