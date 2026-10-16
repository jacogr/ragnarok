## Safe code cannot bypass private/read-only header state through ticketValues.
import ../../../src/codec/header
var value = default(WinnersMarker)
discard value.ticketValues
