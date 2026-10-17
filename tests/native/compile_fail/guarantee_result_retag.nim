## Safe code cannot bypass private guarantee state through status.
import ../../../src/codec/guarantees
var value = default(GuaranteeResult[int])
value.status = GuaranteeError.None
