## Native ticket codec ownership, atomicity and overlap regressions.
import ../../src/tickets

# Produce one fully owned opaque proof with a distinctive final octet.
proc record(attempt: uint8): Ticket =
  var proof: array[784, byte]
  # Vary every byte so partial or swapped copies cannot match a zero-filled record.
  for i in 0..<proof.len: proof[i] = byte(i mod 251)
  Ticket(attempt: TicketAttempt(attempt), proof: TicketProof(proof))

# Verify the complete wire, retained ownership and both failure directions for one attempt.
proc check(attempt: uint8) =
  var values = [record(attempt)]
  var wire: array[790, byte]
  let encoded = encodeTickets(values, TicketLimit(1), wire)
  doAssert encoded.error == TicketError.None and encoded.written == 786
  doAssert wire[0] == 1 and wire[1] == attempt and wire[785] == byte(783 mod 251)
  var output = [record(99), record(98)]
  let before = output
  let decoded = decodeTickets(wire, TicketLimit(1), output)
  doAssert decoded.error == TicketError.None and decoded.count == 1 and decoded.consumed == 786
  doAssert output[0] == values[0] and output[1] == before[1]
  # Successful records retain their own proof bytes after all caller wire storage changes.
  for i in 0..<wire.len: wire[i] = 0
  doAssert output[0] == values[0]
  var short: array[785, byte]
  # Failed encoding preserves every byte, even when the final proof byte alone does not fit.
  for i in 0..<short.len: short[i] = 0xA5
  let oldShort = short
  doAssert encodeTickets(values, TicketLimit(1), short).error == TicketError.OutputTooSmall
  doAssert short == oldShort
  var complete: array[786, byte]
  doAssert encodeTickets(values, TicketLimit(1), complete).error == TicketError.None
  let prior = output
  # A missing final byte cannot commit the already complete attempt or any proof prefix.
  doAssert decodeTickets(complete.toOpenArray(0, 784), TicketLimit(1), output).error ==
      TicketError.Truncated
  doAssert output == prior

# All E1 boundary values remain structural values, independent of Safrole eligibility.
for attempt in [0'u8, 1, 127, 128, 254, 255]: check(attempt)
block:
  var wire: array[1600, byte]
  let values = [record(128)]
  doAssert encodeTickets(values, TicketLimit(1), wire).error == TicketError.None
  let before = wire
  # A trusted alias fixture places typed destination storage directly inside the borrowed wire.
  let destination = cast[ptr UncheckedArray[Ticket]](addr wire[8])
  doAssert decodeTickets(wire, TicketLimit(1), destination.toOpenArray(0, 0)).error ==
      TicketError.AliasedBuffers
  doAssert wire == before
  # Encoding likewise rejects overlapping raw output before the count overwrites a source field.
  let source = cast[ptr UncheckedArray[Ticket]](addr wire[1])
  doAssert encodeTickets(source.toOpenArray(0, 0), TicketLimit(1), wire).error ==
      TicketError.AliasedBuffers
  doAssert wire == before
block:
  var values: array[1, Ticket]
  var wire: array[1, byte]
  # Empty sequences need a real zero count but no typed destination or proof storage.
  doAssert encodeTickets(values.toOpenArray(0, -1), TicketLimit(0), wire).error == TicketError.None
  let decoded = decodeTickets(wire, TicketLimit(0), values.toOpenArray(0, -1))
  doAssert decoded.error == TicketError.None and decoded.count == 0 and decoded.consumed == 1
  # A count above policy is rejected before the missing record payload or destination capacity.
  wire[0] = 2
  doAssert decodeTickets(wire, TicketLimit(1), values).error == TicketError.LimitExceeded

echo "Nim tickets: E1 boundaries, owned proofs, atomic failures and overlap checks passed"
