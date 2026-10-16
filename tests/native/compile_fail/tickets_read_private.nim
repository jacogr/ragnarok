## Safe callers cannot bypass guarded ticket results through recordCount.
import ../../../src/codec/tickets
var value = default(TicketRead)
echo value.recordCount
