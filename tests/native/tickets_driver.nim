# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded trusted batch adapter for the tickets codec; no Python code runs in production.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/tickets

# Decode bounded public fixture text into owned bytes; a dash denotes an empty byte sequence.
proc unhex(text: string): seq[byte] {.raises.} =
  # Empty fields have no byte pair to parse.
  if text == "-": return @[]
  assert text.len mod 2 == 0 and text.len <= 500000
  result = newSeq[byte](text.len div 2)
  # Trusted fixture pairs still require complete hexadecimal encodings.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Reject malformed trusted text before checked byte conversion.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

# Render exact bytes independently from the production encoder.
proc hex(bytes: openArray[byte]): string =
  # Whitespace batch protocols need an explicit representation of empty data.
  if bytes.len == 0: return "-"
  result = ""
  # Each owned byte becomes two canonical lowercase hexadecimal digits.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii())

# Construct one record directly from logical adapter fields rather than decoding the production wire.
proc record(bytes: openArray[byte]): Ticket =
  result = default(Ticket)
  assert bytes.len == 785
  result.attempt = TicketAttempt(bytes[0])
  var proof: array[784, byte] = default(array[784, byte])
  # Preserve opaque proof bytes; the attempt is the preceding separate octet.
  for i in 0..<784: proof[i] = bytes[i+1]
  result.proof = TicketProof(proof)

# Distinct nonzero fields expose partial writes and changes to unused typed output.
proc sentinel(): Ticket =
  var proof = default(array[784, byte])
  # Every proof byte and the separate attempt carry the same observable sentinel.
  for octet in proof.mitems: octet = 0xA5
  Ticket(attempt: TicketAttempt(0xA5), proof: TicketProof(proof))

# Keep the full unsigned fixture domain without narrowing through signed host integers.
proc unsigned(text: string): uint64 =
  var value: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, value) == text.len
  value

# Execute one independent construction/read request and assert whole-destination failure atomicity.
proc request(line: string) {.raises.} =
  let parts = line.splitWhitespace()
  assert parts.len == 4
  let limit = TicketLimit(unsigned(parts[1]))
  let capacity = parseInt(parts[2])
  assert capacity >= 0 and capacity <= 250000
  var input = unhex(parts[3])
  # Encoding source records are constructed from fixed logical fields, not from a decoder round trip.
  if parts[0] == "E":
    assert input.len mod 785 == 0
    var values = newSeq[Ticket](input.len div 785)
    # Every source record owns its entire attempt/proof value.
    for i in 0..<values.len: values[i] = record(input.toOpenArray(785*i, 785*i+784))
    var output = newSeq[byte](capacity)
    # Sentinels catch any destination write before an error return.
    for i in 0..<output.len: output[i] = 0xA5
    let encoded = encodeTickets(values, limit, output)
    # Failed encodes must preserve all destination bytes, including unused capacity.
    if encoded.error != TicketError.None:
      for value in output: assert value == 0xA5
      echo ($encoded.error).toLowerAscii()
    else:
      # Successful output includes only the exact committed wire prefix.
      for i in encoded.written..<output.len: assert output[i] == 0xA5
      echo hex(output.toOpenArray(0, encoded.written-1))
  elif parts[0] == "I":
    # Inspection validates framing without allocating a typed record destination.
    let scanned = inspectTickets(input, limit)
    if scanned.error == TicketError.None: echo $scanned.count & " " & $scanned.consumed
    else: echo ($scanned.error).toLowerAscii() # Failed scans expose only their reason.
  else:
    # Typed storage is separately bounded from the adapter's raw wire capacity.
    assert parts[0] == "D" and capacity <= 256
    var output = newSeq[Ticket](capacity+2)
    # Include nonzero unused records beyond caller capacity to detect speculative initialization.
    for value in output.mitems: value = sentinel()
    let decoded = decodeTickets(input, limit, output.toOpenArray(0, capacity-1))
    # Failed decodes cannot expose partial records or progress.
    if decoded.error != TicketError.None:
      for value in output: assert value == sentinel()
      echo ($decoded.error).toLowerAscii()
    else:
      # Successful records must outlive mutation of every original input byte.
      for octet in input.mitems: octet = 0
      # Both unused caller capacity and the extra sentinel records remain untouched.
      for i in decoded.count..<output.len: assert output[i] == sentinel()
      var logical = newSeq[byte](decoded.count*785)
      # Observe typed fields directly, so decoder/encoder errors cannot cancel each other out.
      for i in 0..<decoded.count:
        logical[785*i] = byte(output[i].attempt)
        let proof = array[784, byte](output[i].proof)
        # Every proof byte must survive owned typed decoding in its original position.
        for j in 0..<784: logical[785*i+1+j] = proof[j]
      echo $decoded.count & " " & hex(logical) & " " & $decoded.consumed

# Batch processing keeps corpus execution deterministic and avoids a process per boundary input.
try:
  # File allocation belongs only to this trusted fixture adapter, never production wire decoding.
  for line in readFile(paramStr(1)).splitLines():
    # Empty physical lines carry no request in the trusted test protocol.
    if line.len > 0: request(line)
except:
  # Missing files or malformed fixture text must fail rather than skip a request.
  quit 2
