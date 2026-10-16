## Safe code cannot bypass private/read-only header state through present.
import ../../../src/codec/header
var value = default(WinnersMarkerInfo)
value.present = true
