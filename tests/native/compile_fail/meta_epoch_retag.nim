## Safe code cannot bypass private/read-only header state through isPresent.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
value.isPresent = true
