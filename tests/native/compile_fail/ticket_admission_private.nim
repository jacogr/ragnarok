## Failed/default admissions must not expose success storage directly.
import ../../../src/state/ticket_admission
let hidden = default(TicketAdmissionResult)
discard hidden.completed
