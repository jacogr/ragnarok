## Trusted local batch adapter: FE <width> <value> or FD <width> <hex bytes>.
import std/[os, strutils]
import ../../src/codec/fixed_unsigned

# Translate typed native errors into stable text labels for the shared harness.
proc errorText(error: FixedError): string =
  case error
  # Unsupported widths have priority over other codec failures.
  of FixedError.InvalidWidth: "invalidwidth"
  # The value cannot be represented without dropping significant bits.
  of FixedError.ValueOutOfRange: "outofrange"
  # The input does not contain the whole requested field.
  of FixedError.Truncated: "truncated"

# Produce one response per trusted request while allowing invalid adapter input to be reported.
for line in readFile(paramStr(1)).splitLines():
  # Ignore blank lines rather than introducing an additional batch request.
  if line.len == 0: continue
  try:
    let parts = line.split(' ', maxsplit = 2)
    # Require the command, width and payload; an empty decode payload still occupies the third part.
    if parts.len != 3: raise newException(ValueError, "request parts")
    let width = ByteWidth(parseInt(parts[1]))
    # Encode a checked unsigned decimal value with the requested width.
    if parts[0] == "FE":
      let encoded = encodeFixed(FixedUnsigned(parseBiggestUInt(parts[2])), width)
      # Emit only actual wire bytes; zero-width success intentionally produces an empty line.
      if encoded.ok:
        var hex = ""
        # Print byte pairs without exposing unused storage in the fixed result array.
        for i in 0..<encoded.encoded.len:
          hex.add(toHex(encoded.encoded.bytes[i], 2).toLowerAscii())
        echo hex
      else:
        # Codec failures are distinct from bad decimal or hex request syntax.
        echo errorText(encoded.error)
    elif parts[0] == "FD":
      # Borrow bytes from a bounded stack buffer for the production decoder.
      let hex = parts[2]
      # Complete pairs and the buffer limit must be checked before conversion or writing.
      if hex.len mod 2 != 0 or hex.len > 128: raise newException(ValueError, "hex length")
      var bytes: array[64, byte]
      # Decode each byte pair after explicitly validating its alphabet.
      for i in 0..<hex.len div 2:
        let pair = hex[i * 2..i * 2 + 1]
        # Reject syntax outside the lowercase-hex adapter protocol.
        for c in pair:
          if c notin {'0'..'9', 'a'..'f'}: raise newException(ValueError, "hex digit")
        bytes[i] = byte(parseHexInt(pair))
      let decoded = decodeFixed(bytes.toOpenArray(0, hex.len div 2 - 1), width)
      # Report both value and consumption to verify prefix behavior, including width zero.
      if decoded.ok:
        echo $uint64(decoded.value) & " " & $decoded.consumed
      else:
        # A native error consumes no field and has no value to print.
        echo errorText(decoded.error)
    else:
      # Reject unknown commands rather than routing them to a codec accidentally.
      echo "inputerror"
  except ValueError:
    # Invalid or overflowing textual input must not terminate the rest of the batch.
    echo "inputerror"
