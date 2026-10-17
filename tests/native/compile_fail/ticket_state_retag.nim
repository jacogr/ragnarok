## Snapshot result storage/discriminator remain private on default and failed publication.
import ../../../src/state/[ticket_state, ticket_admission]
var hidden = default(TicketStateResult)
hidden.status = TicketAdmissionError.None
