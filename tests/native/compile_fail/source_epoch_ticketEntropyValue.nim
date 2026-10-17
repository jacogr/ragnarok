## Safe code cannot bypass private/read-only header state through ticketEntropyValue.
import ../../../src/codec/header
var value = default(EpochMarker)
discard value.ticketEntropyValue
