## Safe code cannot bypass private dispute state through completed.
import ../../../src/codec/disputes
var value = default(DisputeResult[DisputeInfo])
discard value.completed
