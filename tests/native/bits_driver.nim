## Trusted batch adapter compares independent logical bits, exact wire prefixes and immutable owner behavior.
import std/[os, strutils]
import ../../src/bitstrings

# Require success before observing any completed native result or progress.
proc checked[T](parsed: BitResult[T]): T =
  doAssert parsed.error == BitError.None
  parsed.value

# Decode trusted hexadecimal request transport into separately mutable byte storage.
proc unhex(text: string): seq[byte] =
  # Empty byte strings need a token that survives whitespace splitting.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0 and text.len <= 2*1024*1024
  result = newSeq[byte](text.len div 2)
  # Each octet is independent of the text buffer and may be overwritten after owner capture.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Exact octet observations distinguish canonical framing from a same-codec logical round trip.
proc hex(value: openArray[byte]): string =
  # Use one token even for fixed empty bitstrings, which encode to no bytes.
  if value.len == 0: return "-"
  # Preserve every octet's position, including leading zero bytes.
  for octet in value: result.add(toHex(octet, 2).toLowerAscii())

# Trusted logical source text is a sequence of Boolean values rather than packed production wire.
proc logical(text: string): seq[bool] =
  # A validated empty bitstring is distinct from a missing source owner.
  if text == "-": return @[]
  result = newSeq[bool](text.len)
  # Reject malformed transport; production encoders accept typed bool values only.
  for i, digit in text:
    doAssert digit in {'0', '1'}
    result[i] = digit == '1'

# Assert complete failure atomicity and untouched success suffix for a requested caller-owned destination.
proc emitted(parsed: BitResult[int], output: openArray[byte]) =
  # Failed operations may expose only their reason and must not modify any destination byte.
  if parsed.error != BitError.None:
    # The entire supplied output remains at its canary value.
    for octet in output: doAssert octet == 0xA5
    echo ($parsed.error).toLowerAscii()
  else:
    # Bytes beyond the completed frame remain unrelated caller capacity.
    for i in parsed.value..<output.len: doAssert output[i] == 0xA5
    echo hex(output.toOpenArray(0, parsed.value-1))

# Decode logical fields, overwrite original bytes and test both fixed and variable re-emission through matching owners.
proc decoded(parsed: BitResult[BitsRead], input: var seq[byte]) =
  # No owner or logical count can be read from a rejected frame.
  if parsed.error != BitError.None:
    echo ($parsed.error).toLowerAscii()
    return
  let read = parsed.value
  let info = checked(bitsInfo(read.owner))
  doAssert uint64(info.count) <= 1048576
  # Independent owner bytes must survive modification of the entire original input, including its suffix.
  for i in 0..<input.len: input[i] = 0xFF
  var bits = ""
  # Every logical bit is observed independently through the matching retained owner.
  for i in 0..<int(uint64(info.count)): bits.add(if checked(bitAt(read.owner, i)): '1' else: '0')
  doAssert bitAt(read.owner, -1).error == BitError.InvalidIndex
  doAssert bitAt(read.owner, int(uint64(info.count))).error == BitError.InvalidIndex
  var fixed = newSeq[byte](info.packedBytes+3)
  # Canary suffixes catch excessive copies during exact packed-payload re-emission.
  for i in 0..<fixed.len: fixed[i] = 0xA5
  doAssert checked(encodeOwnedFixedBits(read.owner, info.count, BitLimit(high(uint64)), fixed)) ==
      info.packedBytes
  # Re-emission may not overwrite any bytes beyond the fixed packed payload.
  for i in info.packedBytes..<fixed.len: doAssert fixed[i] == 0xA5
  var variable = newSeq[byte](info.packedBytes+12)
  # Variable reframing adds only its canonical bit-count discriminator.
  for i in 0..<variable.len: variable[i] = 0xA5
  let written = checked(encodeOwnedBits(read.owner, BitLimit(high(uint64)), variable))
  # Spare variable-frame capacity stays unchanged too.
  for i in written..<variable.len: doAssert variable[i] == 0xA5
  echo $read.consumed & " " & $uint64(info.count) & " " & (if bits.len == 0: "-" else: bits) &
    " " & hex(fixed.toOpenArray(0, info.packedBytes-1)) & " " & hex(variable.toOpenArray(0, written-1))

# Dispatch one trusted operation while leaving untrusted codec bytes to the production validator.
proc request(parts: seq[string]) =
  # Standalone Boolean decoding must reject all octets outside 0/1.
  if parts[0] == "BD":
    let parsed = decodeBoolean(unhex(parts[1]))
    # Failure cannot authorize a default false value or consumed progress.
    if parsed.error != BitError.None: echo ($parsed.error).toLowerAscii()
    else:
      # Copy the complete canonical Boolean and exact prefix extent.
      echo $ord(parsed.value.value) & " " & $parsed.value.consumed
    return
  # Boolean encoders receive a logical value independently of any decoder.
  if parts[0] == "BE":
    var output = newSeq[byte](parseInt(parts[2]))
    # Every requested destination starts with an independently observable canary.
    for i in 0..<output.len: output[i] = 0xA5
    emitted(encodeBoolean(parts[1] == "1", output), output)
    return
  let count = BitCount(uint64(parseBiggestUInt(parts[2])))
  let limit = BitLimit(uint64(parseBiggestUInt(parts[3])))
  # Decoder and encoder test inputs are independently constructed in Python.
  if parts[0] == "D":
    var input = unhex(parts[4])
    # Variable framing ignores the transport's fixed-count placeholder.
    if parts[1] == "V": decoded(decodeBits(input, limit), input)
    else:
      # Fixed schemas obtain their logical count from the caller, never from payload bytes.
      decoded(decodeFixedBits(input, count, limit), input)
  else:
    # Typed bool sources avoid obtaining encoder values from a production decoder.
    let values = logical(parts[5])
    var output = newSeq[byte](parseInt(parts[4]))
    # Failed preflight and unused success capacity must preserve the original destination.
    for i in 0..<output.len: output[i] = 0xA5
    # Variable encoding derives its bit count directly from the logical source sequence.
    if parts[1] == "V": emitted(encodeBits(values, limit, output), output)
    else:
      # Fixed encoding additionally requires exact caller-specified cardinality.
      emitted(encodeFixedBits(values, count, limit, output), output)

# Requests do not retain native input/output buffers across independent operations.
for line in lines(paramStr(1)):
  # Empty trusted batch lines contain no codec operation.
  if line.len > 0: request(line.splitWhitespace())
