## Fixed-width batch adapter; preserve invalid widths and reject textual uint64/host-int overflow.
import std/[assertions, cmdline, strutils, syncio]
import ./batch_support
import ../../src/codec/fixed_unsigned

# Preserve stable wire-policy reasons rather than interpreting unsupported widths as syntax errors.
proc errorText(error: FixedError): string =
  case error
  of FixedError.InvalidWidth: "invalidwidth" # Width validation precedes reading or shifting.
  of FixedError.ValueOutOfRange: "outofrange" # Encoding cannot discard significant bits.
  of FixedError.Truncated: "truncated" # Decoding requires every requested byte.

# One textual request may deliberately exceed host/uint64 limits; handle that before codec construction.
proc request(line: string) =
  let parts = line.split(' ', maxsplit = 2)
  var width: int = 0
  if parts.len != 3 or not parseSigned(parts[1], width):
    echo "inputerror" # Empty decode data still has its explicit third part.
    return
  if parts[0] == "FE":
    var value: uint64 = 0
    if not parseUnsigned(parts[2], value):
      echo "inputerror" # Overflow and negative values must never narrow or wrap.
      return
    let encoded = encodeFixed(FixedUnsigned(value), ByteWidth(width))
    if encoded.ok:
      var hex = ""
      # Zero-width success intentionally prints an empty response line.
      for i in 0..<encoded.encoded.len:
        hex.add(toHex(int(encoded.encoded.bytes[i]), 2).toLowerAscii())
      echo hex
    else:
      echo errorText(encoded.error) # No completed encoded array is available on failure.
  elif parts[0] == "FD":
    let hex = parts[2]
    if hex.len mod 2 != 0 or hex.len > 128:
      echo "inputerror" # Bound the test transport independently of requested width.
      return
    var bytes = newSeq[byte](hex.len div 2)
    # Decode only supplied bytes; unsupported widths still reach the native width check.
    for i in 0..<bytes.len: bytes[i] = octet(hex[2*i..2*i+1])
    let decoded = decodeFixed(bytes, ByteWidth(width))
    if decoded.ok:
      echo $uint64(decoded.value) & " " & $decoded.consumed # Include prefix consumption, even for width zero.
    else:
      echo errorText(decoded.error) # A failed prefix has no observable default value.
  else:
    echo "inputerror" # Unknown command never selects a codec accidentally.

# Retain empty payload spaces while discarding only truly empty batch lines.
try:
  for line in readFile(paramStr(1)).splitLines():
    if line.len > 0: request(line) # Final newline does not add an observation.
except:
  # Fixture I/O failures are fatal and cannot masquerade as production codec errors.
  quit 2
