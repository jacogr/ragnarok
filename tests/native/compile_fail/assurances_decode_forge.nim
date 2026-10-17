## Safe callers cannot bypass guarded assurance results through status.
import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
discard AssuranceDecodeResult(status: AssuranceError.None)
