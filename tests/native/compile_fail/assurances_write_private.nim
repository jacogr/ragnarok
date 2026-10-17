## Safe callers cannot bypass guarded assurance results through byteWritten.
import ../../../src/codec/assurances
var value = default(AssuranceWriteResult)
echo value.byteWritten
