## Safe code cannot bypass private dispute state through error.
import ../../../src/codec/disputes
var value = default(DisputeResult[int])
value.error = DisputeError.None
