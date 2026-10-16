## Safe code cannot bypass private/read-only header state through ticketCount.
import ../../../src/codec/header
var value = default(WinnersMarkerInfo)
discard value.ticketCount
