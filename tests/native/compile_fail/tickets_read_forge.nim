## Safe callers cannot bypass guarded ticket results through status.
import ../../../src/codec/tickets
var value = default(TicketRead)
discard TicketRead(status: TicketError.None)
