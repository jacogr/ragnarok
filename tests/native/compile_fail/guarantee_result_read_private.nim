## Safe code cannot bypass private guarantee state through completed.
import ../../../src/codec/guarantees
var value = default(GuaranteeResult[GuaranteeRead])
discard value.completed
