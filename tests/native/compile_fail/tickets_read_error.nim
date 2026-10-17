## Safe callers cannot bypass guarded ticket results through error.
import ../../../src/codec/tickets
var value = default(TicketRead)
value.error = TicketError.None
