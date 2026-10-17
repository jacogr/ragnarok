## Callers cannot forge successful admission by retagging a failed candidate result.
import ../../../src/state/ticket_admission
var hidden = default(TicketAdmissionResult)
hidden.status = TicketAdmissionError.None
