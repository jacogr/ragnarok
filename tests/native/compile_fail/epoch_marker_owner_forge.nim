## Safe code cannot bypass private/read-only header state through data.
import ../../../src/codec/header
var value = default(OwnedEpochMarker)
discard OwnedEpochMarker(data: nil)
