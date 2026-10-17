## Safe callers cannot bypass guarded ticket results through error.
import ../../../src/codec/tickets
var value = default(TicketWrite)
value.error = TicketError.None
