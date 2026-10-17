## Safe code cannot bypass private dispute state through status.
import ../../../src/codec/disputes
var value = default(DisputeResult[int])
discard DisputeResult[int](status: DisputeError.None)
