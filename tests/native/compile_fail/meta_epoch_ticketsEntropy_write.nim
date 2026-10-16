## Safe code cannot bypass private/read-only header state through ticketsEntropy.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
value.ticketsEntropy = TicketsEntropy(default(array[32, byte]))
