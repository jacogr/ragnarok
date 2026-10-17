## Safe callers cannot bypass guarded ticket results through consumed.
import ../../../src/codec/tickets
var value = default(TicketRead)
value.consumed = 0
