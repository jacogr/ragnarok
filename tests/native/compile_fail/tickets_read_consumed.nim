## Safe callers cannot bypass guarded ticket results through byteConsumed.
import ../../../src/codec/tickets
var value = default(TicketRead)
echo value.byteConsumed
