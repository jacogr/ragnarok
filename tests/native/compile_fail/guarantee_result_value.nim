## Safe code cannot bypass private guarantee state through value.
import ../../../src/codec/guarantees
var value = default(GuaranteeResult[int])
value.value = 0
