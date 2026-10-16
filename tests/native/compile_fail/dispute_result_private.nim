## Safe code cannot bypass private dispute state through completed.
import ../../../src/codec/disputes
var value = default(DisputeResult[DisputesRead])
discard value.completed
