## Safe code cannot bypass private/read-only header state through isPresent.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
discard EpochMarkerInfo(isPresent: true)
