## Safe code cannot bypass private guarantee state through data.
import ../../../src/codec/guarantees
var value = default(OwnedGuarantees)
discard OwnedGuarantees(data: nil)
