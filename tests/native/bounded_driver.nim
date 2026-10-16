## Trusted batch adapter: BE/BD for bytes, SE/SD for fixed-width sequences.
import std/[assertions, cmdline, strutils, syncio]
import ./batch_support
import ./ownership_checks
import ../../src/codec/[bounded, fixed_unsigned]

# Decode bounded adapter hex, allocating only for the actual trusted request text.
proc parseBytes(text: string): seq[byte] =
  # A dash represents an empty payload, keeping every request token explicit.
  if text == "-": return @[]
  # Reject incomplete pairs and requests beyond this adapter's 32 KiB capacity.
  if text.len mod 2 != 0 or text.len > 65536: assert false, "hex length"
  result = newSeq[byte](text.len div 2)
  # Validate the alphabet before converting each pair into a byte.
  for i in 0..<result.len:
    let pair = text[i * 2..i * 2 + 1]
    for c in pair:
      # Only lowercase hex belongs to this test protocol.
      if c notin {'0'..'9', 'a'..'f'}: assert false, "hex digit"
    result[i] = octet(pair)

# Print actual encoded or decoded payload bytes; dash denotes an empty payload.
proc hexText(bytes: openArray[byte]): string =
  # Empty blobs need an explicit token before the reported consumed length.
  if bytes.len == 0: return "-"
  result = ""
  # Convert exactly the passed span rather than unused caller-owned storage.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii())

# Parse a bounded output capacity rather than letting textual requests choose arbitrary allocations.
proc capacity(text: string, maximum: int): int =
  result = integer(text)
  # Adapter bounds differ from production resource limits and guard only test utility storage.
  if result < 0 or result > maximum: assert false, "capacity"

# Route trusted requests to the checked production APIs; each nonempty line receives one result.
try:
  for line in readFile(paramStr(1)).splitLines():
    # A file's final newline is not a codec request.
    if line.len == 0: continue
    let parts = line.split(' ')
    # Byte encoding needs a resource limit, output capacity and explicit hex payload.
    if parts[0] == "BE" and parts.len == 4:
      let value = parseBytes(parts[3])
      var output = newSeq[byte](capacity(parts[2], 32768))
      for b in output.mitems: b = 77 # Sentinel detects partial writes on failed operations.
      let encoded = encodeBytes(value, ByteLimit(unsigned(parts[1])), output)
      # Success prints only the written frame; error paths must leave the entire output untouched.
      if encoded.error == ContainerError.None: echo hexText(output.toOpenArray(0, encoded.written - 1))
      else:
        for b in output: assert b == 77 # Verify the encoder's atomic-failure contract.
        echo ($encoded.error).toLowerAscii()
    elif parts[0] == "BD" and parts.len == 3:
      # The byte decoder returns indices into this retained local buffer, with no output allocation.
      let wire = parseBytes(parts[2])
      let decoded = decodeBytesBorrowed(wire, ByteLimit(unsigned(parts[1])))
      if decoded.error == ContainerError.None:
        # Verify the owned snapshot against every successful shared byte-string request.
        checkOwnedBytes(wire, ByteLimit(unsigned(parts[1])), decoded)
        # Only the payload span belongs in the response; prefix and trailing bytes are excluded.
        echo hexText(wire.toOpenArray(decoded.offset, decoded.offset + decoded.length - 1)) & " " &
            $decoded.consumed
      else:
        # The typed wire/policy error carries no usable span.
        echo ($decoded.error).toLowerAscii()
    elif parts[0] == "SE" and parts.len == 5:
      # Fixed-width values are parsed individually with checked uint64 conversion, capped at 512 elements.
      var values: seq[FixedUnsigned] = @[]
      if parts[4] != "-":
        # The dash is an empty sequence, not a numeric element.
        let numbers = parts[4].split(',')
        if numbers.len > 512: assert false, "elements" # Bound trusted utility storage.
        for number in numbers: values.add(FixedUnsigned(unsigned(number)))
      var output = newSeq[byte](capacity(parts[3], 32768))
      for b in output.mitems: b = 77 # Guard every possible error against a partial commit.
      let encoded = encodeSequence(values, ByteWidth(integer(parts[1])),
                                   ElementLimit(unsigned(parts[2])), output)
      if encoded.error == ContainerError.None:
        # A variable sequence always includes its count prefix, even when the count is zero.
        echo hexText(output.toOpenArray(0, encoded.written - 1))
      else:
        for b in output: assert b == 77 # Late element failures must also preserve all output bytes.
        echo ($encoded.error).toLowerAscii()
    elif parts[0] == "SD" and parts.len == 5:
      # Caller-owned output capacity is independent from the maximum permitted wire count.
      let wire = parseBytes(parts[4])
      var output = newSeq[FixedUnsigned](capacity(parts[3], 512))
      for item in output.mitems: item = FixedUnsigned(999) # Sentinel checks failed-decode atomicity.
      let decoded = decodeSequence(wire, ByteWidth(integer(parts[1])),
                                   ElementLimit(unsigned(parts[2])), output)
      if decoded.error == ContainerError.None:
        var numbers: seq[string] = @[]
        # Report only the initialized prefix; unused output entries remain the caller's values.
        for i in 0..<decoded.count: numbers.add($uint64(output[i]))
        let text = if numbers.len == 0: "-" else: numbers.join(",")
        echo text & " " & $decoded.consumed
      else:
        for item in output: assert uint64(item) == 999 # No failed decode may change an output entry.
        echo ($decoded.error).toLowerAscii()
    else:
      # Wrong command or token count must not reach a production decoder accidentally.
      echo "inputerror"
except:
  # Fixture I/O failures are fatal and cannot masquerade as production codec errors.
  quit 2
