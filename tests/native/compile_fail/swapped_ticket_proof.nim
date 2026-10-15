import ../../../src/tickets
# Entry identities cannot occupy the opaque RingVRF proof domain.
let wrong = Ticket(proof: TicketAttempt(1))
discard wrong
