## Safe callers cannot bypass guarded ticket results through count.
import ../../../src/codec/tickets
var value = default(TicketRead)
value.count = 0
