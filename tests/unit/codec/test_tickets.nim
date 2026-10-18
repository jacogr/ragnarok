# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native ticket codec ownership, atomicity and overlap regressions.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/tickets

# Produce one fully owned opaque proof with a distinctive final octet.
proc record(attempt: uint8): Ticket =
  var proof: array[784, byte] = default(array[784, byte])
  # Vary every byte so partial or swapped copies cannot match a zero-filled record.
  for i in 0..<proof.len: proof[i] = byte(i mod 251)
  Ticket(attempt: TicketAttempt(attempt), proof: TicketProof(proof))

# Verify the complete wire, retained ownership and both failure directions for one attempt.
proc check(attempt: uint8) =
  var values = [record(attempt)]
  var wire: array[790, byte] = default(array[790, byte])
  let encoded = encodeTickets(values, TicketLimit(1), wire)
  assert encoded.error == TicketError.None and encoded.written == 786
  assert wire[0] == 1 and wire[1] == attempt and wire[785] == byte(783 mod 251)
  var output = [record(99), record(98)]
  let before = output
  let decoded = decodeTickets(wire, TicketLimit(1), output)
  assert decoded.error == TicketError.None and decoded.count == 1 and decoded.consumed == 786
  assert output[0] == values[0] and output[1] == before[1]
  let inspected = inspectTickets(wire, TicketLimit(1))
  assert inspected.error == TicketError.None and inspected.count == 1 and inspected.consumed == 786
  # Successful records retain their own proof bytes after all caller wire storage changes.
  for i in 0..<wire.len: wire[i] = 0
  assert output[0] == values[0]
  var short: array[785, byte] = default(array[785, byte])
  # Failed encoding preserves every byte, even when the final proof byte alone does not fit.
  for i in 0..<short.len: short[i] = 0xA5
  let oldShort = short
  assert encodeTickets(values, TicketLimit(1), short).error == TicketError.OutputTooSmall
  assert short == oldShort
  var complete: array[786, byte] = default(array[786, byte])
  assert encodeTickets(values, TicketLimit(1), complete).error == TicketError.None
  let prior = output
  # A missing final byte cannot commit the already complete attempt or any proof prefix.
  assert decodeTickets(complete.toOpenArray(0, 784), TicketLimit(1), output).error ==
      TicketError.Truncated
  assert output == prior

# All E1 boundary values remain structural values, independent of Safrole eligibility.
for attempt in [0'u8, 1, 127, 128, 254, 255]: check(attempt)
block:
  var wire: array[1600, byte] = default(array[1600, byte])
  let values = [record(128)]
  assert encodeTickets(values, TicketLimit(1), wire).error == TicketError.None
  let before = wire
  # A trusted alias fixture places typed destination storage directly inside the borrowed wire.
  let destination = cast[ptr array[1, Ticket]](addr wire[8])
  assert decodeTickets(wire, TicketLimit(1), destination[].toOpenArray(0, 0)).error ==
      TicketError.AliasedBuffers
  assert wire == before
  # Even typed writes wholly inside unrelated trailing input must preserve the full borrowed source.
  let trailing = cast[ptr array[1, Ticket]](addr wire[800])
  assert decodeTickets(wire, TicketLimit(1), trailing[].toOpenArray(0, 0)).error ==
      TicketError.AliasedBuffers
  assert wire == before
  # Encoding likewise rejects overlapping raw output before the count overwrites a source field.
  let source = cast[ptr array[1, Ticket]](addr wire[1])
  assert encodeTickets(source[].toOpenArray(0, 0), TicketLimit(1), wire).error ==
      TicketError.AliasedBuffers
  assert wire == before
block:
  var values: array[1, Ticket] = default(array[1, Ticket])
  var wire: array[1, byte] = default(array[1, byte])
  # Empty sequences need a real zero count but no typed destination or proof storage.
  assert encodeTickets(values.toOpenArray(0, -1), TicketLimit(0), wire).error == TicketError.None
  let decoded = decodeTickets(wire, TicketLimit(0), values.toOpenArray(0, -1))
  assert decoded.error == TicketError.None and decoded.count == 0 and decoded.consumed == 1
  # A count above policy is rejected before the missing record payload or destination capacity.
  wire[0] = 2
  assert decodeTickets(wire, TicketLimit(1), values).error == TicketError.LimitExceeded

let missingWrite = default(TicketWrite)
let missingRead = default(TicketRead)
assert missingWrite.error == TicketError.Uninitialized and missingRead.error ==
    TicketError.Uninitialized

echo "Tickets: E1 boundaries, owned proofs, atomic failures and overlap checks passed"
