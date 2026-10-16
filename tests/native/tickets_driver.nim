## Bounded trusted batch adapter for the tickets codec; no Python code runs in production.
import std/[os, strutils]
import ../../src/codec/tickets

# Decode bounded public fixture text into owned bytes; a dash denotes an empty byte sequence.
proc unhex(text: string): seq[byte] =
  # Empty fields have no byte pair to parse.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0 and text.len <= 500000
  result = newSeq[byte](text.len div 2)
  # Trusted fixture pairs still require complete hexadecimal encodings.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Render exact bytes independently from the production encoder.
proc hex(bytes: openArray[byte]): string =
  # Whitespace batch protocols need an explicit representation of empty data.
  if bytes.len == 0: return "-"
  # Each owned byte becomes two canonical lowercase hexadecimal digits.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

# Construct one record directly from logical adapter fields rather than decoding the production wire.
proc record(bytes: openArray[byte]): Ticket =
  doAssert bytes.len == 785
  result.attempt = TicketAttempt(bytes[0])
  var proof: array[784, byte]
  # Preserve opaque proof bytes; the attempt is the preceding separate octet.
  for i in 0..<784: proof[i] = bytes[i+1]
  result.proof = TicketProof(proof)

# Execute one independent construction/read request and assert whole-destination failure atomicity.
proc request(line: string) =
  let parts = line.splitWhitespace()
  doAssert parts.len == 4
  let limit = TicketLimit(parseBiggestUInt(parts[1]))
  let capacity = parseInt(parts[2])
  doAssert capacity >= 0 and capacity <= 250000
  let input = unhex(parts[3])
  # Encoding source records are constructed from fixed logical fields, not from a decoder round trip.
  if parts[0] == "E":
    doAssert input.len mod 785 == 0
    var values = newSeq[Ticket](input.len div 785)
    # Every source record owns its entire attempt/proof value.
    for i in 0..<values.len: values[i] = record(input.toOpenArray(785*i, 785*i+784))
    var output = newSeq[byte](capacity)
    # Sentinels catch any destination write before an error return.
    for i in 0..<output.len: output[i] = 0xA5
    let encoded = encodeTickets(values, limit, output)
    # Failed encodes must preserve all destination bytes, including unused capacity.
    if encoded.error != TicketError.None:
      for value in output: doAssert value == 0xA5
      echo ($encoded.error).toLowerAscii()
    else:
      # Successful output includes only the exact committed wire prefix.
      for i in encoded.written..<output.len: doAssert output[i] == 0xA5
      echo hex(output.toOpenArray(0, encoded.written-1))
  else:
    # Typed storage is separately bounded from the adapter's raw wire capacity.
    doAssert parts[0] == "D" and capacity <= 256
    var output = newSeq[Ticket](capacity)
    let decoded = decodeTickets(input, limit, output)
    # Failed decodes cannot expose partial records or progress.
    if decoded.error != TicketError.None:
      for value in output: doAssert value == default(Ticket)
      echo ($decoded.error).toLowerAscii()
    else:
      var logical = newSeq[byte](decoded.count*785)
      # Observe typed fields directly, so decoder/encoder errors cannot cancel each other out.
      for i in 0..<decoded.count:
        logical[785*i] = byte(output[i].attempt)
        let proof = array[784, byte](output[i].proof)
        # Every proof byte must survive owned typed decoding in its original position.
        for j in 0..<784: logical[785*i+1+j] = proof[j]
      echo $decoded.count & " " & hex(logical) & " " & $decoded.consumed

# Batch processing keeps corpus execution deterministic and avoids a process per boundary input.
for line in lines(paramStr(1)):
  # Empty physical lines carry no request in the trusted test protocol.
  if line.len > 0: request(line)
