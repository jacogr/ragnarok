## Trusted independent assurances adapter, including deliberate overlap and lifetime probes.
import std/[os, strutils]
import ../../src/codec/assurances

# Bound and validate test hex independently of the production wire decoder.
proc unhex(text: string): seq[byte] =
  # Dash preserves an empty line-protocol token.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0 and text.len <= 300000
  result = newSeq[byte](text.len div 2)
  # Validate both nibbles before constructing each trusted source byte.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    for c in pair:
      # Uppercase and nonhex text are harness errors.
      doAssert c in {'0'..'9', 'a'..'f'}
    result[i] = byte(parseHexInt(pair))

# Print every actual output byte, using dash for an empty logical sequence.
proc hexText(data: openArray[byte]): string =
  # An explicit empty token keeps subsequent numeric fields distinct.
  if data.len == 0: return "-"
  # Hex conversion is confined to the trusted adapter boundary.
  for value in data: result.add(toHex(value, 2).toLowerAscii())

# Parse a bounded host allocation size; production resource limits remain separate.
proc capacity(text: string, maximum: int): int =
  result = parseInt(text)
  doAssert result >= 0 and result <= maximum

# Initialize every named field, including unused bitset bytes, for atomicity tests.
proc sentinel(): Assurance =
  # Make all 32 anchor bytes observable after a failed decode.
  for i in 0..<32: result.anchor.bytes[i] = 77
  # Unused storage must survive failure too.
  for i in 0..<43: result.bits.bytes[i] = 77
  result.validator = ValidatorIndex(77)
  # Signatures have their own independent identity domain.
  for i in 0..<64: result.signature.bytes[i] = 77

# Construct logical source fields without calling the new wire decoder.
proc records(data: openArray[byte]): seq[Assurance] =
  doAssert data.len mod 141 == 0
  result = newSeq[Assurance](data.len div 141)
  # Logical records retain full native bitset storage regardless of configured wire width.
  for i in 0..<result.len:
    let start = i*141
    # Construct the declared anchor directly.
    for j in 0..<32: result[i].anchor.bytes[j] = data[start+j]
    # Include octets outside the selected profile to test encoder rejection.
    for j in 0..<43: result[i].bits.bytes[j] = data[start+32+j]
    result[i].validator = ValidatorIndex(uint16(data[start+75]) or (uint16(data[start+76]) shl 8))
    # Preserve all independent signature bytes.
    for j in 0..<64: result[i].signature.bytes[j] = data[start+77+j]

# Render named fields independently of encoder ordering and native struct padding.
proc logical(values: openArray[Assurance]): seq[byte] =
  # Every record contributes the same complete fixed logical layout.
  for value in values:
    result.add(value.anchor.bytes)
    result.add(value.bits.bytes)
    result.add(byte(uint16(value.validator) and 255))
    result.add(byte(uint16(value.validator) shr 8))
    result.add(value.signature.bytes)

# Verify full sentinel spans, including bytes beyond the encoder's returned extent.
proc unchanged(data: openArray[byte]) =
  # Partial commits are failures even if returned metadata hides them.
  for value in data: doAssert value == 77

# Execute frozen equivalent operations with independent construction and ownership assertions.
proc request(p: seq[string]) =
  let config = AssuranceConfig(cores: CoreCount(parseBiggestUInt(p[1])),
                               validators: ValidatorCount(parseBiggestUInt(p[2])))
  case p[0]
  of "E":
    # Typed source construction is independent of the new wire decode operation.
    let values = records(unhex(p[4]))
    let cap = capacity(p[3], 150000)
    var output = newSeq[byte](cap+3)
    # Fill active and trailing destination bytes before calling production code.
    for value in output.mitems: value = 77
    let encoded = encodeAssurances(values, config, output.toOpenArray(0, cap-1))
    if encoded.error != AssuranceError.None:
      # A failed final record must preserve every prior output byte.
      unchanged(output)
      echo ($encoded.error).toLowerAscii()
    else:
      # Success cannot write beyond its returned extent.
      unchanged(output.toOpenArray(encoded.written, output.high))
      echo hexText(output.toOpenArray(0, encoded.written-1))
  of "D":
    # Decode into bounded typed capacity, with two extra records that must survive unchanged.
    var data = unhex(p[4])
    let saved = data
    let cap = capacity(p[3], 1024)
    var output = newSeq[Assurance](cap+2)
    # Explicit initialization makes late failure observable across every named field.
    for value in output.mitems: value = sentinel()
    let before = logical(output)
    let decoded = decodeAssurances(data, config, output.toOpenArray(0, cap-1))
    if decoded.error != AssuranceError.None:
      # Failed decoders must preserve the entire typed destination.
      doAssert logical(output) == before
      echo ($decoded.error).toLowerAscii()
    else:
      # Overwrite source bytes before inspecting retained decoded fields.
      for value in data.mitems: value = 0
      doAssert logical(output.toOpenArray(decoded.count, output.high)) == before[
          decoded.count*141..^1]
      let bytes = logical(output.toOpenArray(0, decoded.count-1))
      var encoded = newSeq[byte](decoded.consumed)
      let check = encodeAssurances(output.toOpenArray(0, decoded.count-1), config, encoded)
      doAssert check.error == AssuranceError.None and check.written == decoded.consumed
      doAssert encoded == saved[0..<decoded.consumed]
      echo $decoded.count & " " & hexText(bytes) & " " & $decoded.consumed
  else:
    # Unsafe byte views are limited to deliberate trusted overlap tests.
    let data = unhex(p[3])
    var values: seq[Assurance]
    var count = 0
    if p[0] == "XE":
      # One extra record reserves enough memory for the wire count prefix.
      values = records(data)
      count = values.len
      values.add(sentinel())
    else:
      # A typed allocation gives the aliased decode destination proper alignment.
      doAssert p[0] == "XD"
      values = newSeq[Assurance](data.len div 99+3)
    let size = values.len*sizeof(Assurance)
    let raw = cast[ptr UncheckedArray[byte]](addr values[0])
    if p[0] == "XD":
      # Copy a valid external wire image over the aligned typed output storage.
      copyMem(addr raw[0], unsafeAddr data[0], data.len)
    let saved = @(raw.toOpenArray(0, size-1))
    if p[0] == "XE":
      # Pass overlapping typed and byte views only after explicitly bypassing normal safety.
      let encoded = encodeAssurances(values.toOpenArray(0, count-1), config, raw.toOpenArray(0, size-1))
      doAssert encoded.error == AssuranceError.AliasedBuffers
      echo ($encoded.error).toLowerAscii()
    else:
      # Full-input overlap must be rejected before any typed record commit.
      let decoded = decodeAssurances(raw.toOpenArray(0, data.high), config, values)
      doAssert decoded.error == AssuranceError.AliasedBuffers
      echo ($decoded.error).toLowerAscii()
    doAssert @(raw.toOpenArray(0, size-1)) == saved

# A single native process handles all frozen requests with no Python runtime involvement.
proc main() =
  doAssert paramCount() == 1
  # Line iteration avoids arbitrary input-dependent native protocol allocation.
  for line in lines(paramStr(1)):
    if line.len == 0:
      # A trailing newline is not a codec operation.
      continue
    let parts = line.splitWhitespace()
    doAssert parts.len in [4, 5]
    request(parts)

main()
