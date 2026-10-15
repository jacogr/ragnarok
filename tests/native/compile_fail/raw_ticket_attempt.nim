import ../../../src/tickets
# Host octets require an explicit conversion into ticket-entry identity.
let wrong = Ticket(attempt: 128'u8)
discard wrong
