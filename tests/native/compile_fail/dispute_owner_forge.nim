## Safe code cannot bypass private dispute state through data.
import ../../../src/codec/disputes
var value = default(OwnedDisputes)
discard OwnedDisputes(data: nil)
