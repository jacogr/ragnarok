## Safe code cannot bypass private guarantee state through error.
import ../../../src/codec/guarantees
var value = default(GuaranteeResult[int])
value.error = GuaranteeError.None
