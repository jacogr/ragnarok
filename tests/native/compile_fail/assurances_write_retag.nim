## Safe callers cannot bypass guarded assurance results through status.
import ../../../src/codec/assurances
var value = default(AssuranceWriteResult)
value.status = AssuranceError.None
