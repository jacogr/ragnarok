## Safe callers cannot bypass guarded ticket results through status.
import ../../../src/codec/tickets
var value = default(TicketWrite)
discard TicketWrite(status: TicketError.None)
