## Safe code cannot bypass private/read-only header state through tickets.
import ../../../src/codec/header
var value = default(WinnersMarkerInfo)
value.tickets = 0
