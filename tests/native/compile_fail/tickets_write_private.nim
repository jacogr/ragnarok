## Safe callers cannot bypass guarded ticket results through byteWritten.
import ../../../src/codec/tickets
var value = default(TicketWrite)
echo value.byteWritten
