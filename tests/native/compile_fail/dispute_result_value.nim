## Safe code cannot bypass private dispute state through value.
import ../../../src/codec/disputes
var value = default(DisputeResult[int])
value.value = 0
