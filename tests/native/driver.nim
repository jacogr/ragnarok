## Batch test/fuzz adapter. Request file is trusted local harness input.
import std/[os, strutils]
import ../../src/codec/natural

# Process one trusted batch request at a time, producing one response for each nonempty line.
for line in readFile(paramStr(1)).splitLines():
  # Ignore blank lines so a final newline does not create a request.
  if line.len == 0: continue
  # Convert malformed decimal/hex input into a response while allowing the remaining batch to run.
  try:
    # Encode a decimal uint64; the parser rejects values outside its unsigned range.
    if line.startsWith("E "):
      let encoded = encode(JamNatural(parseBiggestUInt(line[2..^1])))
      var hex = ""
      # Print exactly the used bytes as lowercase hex, excluding unused output storage.
      for i in 0..<encoded.len: hex.add(toHex(encoded.bytes[i], 2).toLowerAscii())
      echo hex
    elif line.startsWith("D "):
      # Decode hex input so arbitrary byte sequences can exercise the production decoder.
      let hex = line[2..^1]
      # Require complete byte pairs and enforce the adapter buffer limit before writing into it.
      if hex.len mod 2 != 0 or hex.len > 128: raise newException(ValueError, "hex length")
      var bytes: array[64, byte]
      # Translate each pair of hex characters into one byte in the fixed-size input buffer.
      for i in 0..<hex.len div 2:
        let pair = hex[i * 2..i * 2 + 1]
        # Validate both digits explicitly so the generic parser cannot accept unexpected syntax.
        for c in pair:
          # Reject characters outside the lowercase hex alphabet used by the shared test protocol.
          if c notin {'0'..'9', 'a'..'f'}: raise newException(ValueError, "hex digit")
        bytes[i] = byte(parseHexInt(pair))
      let decoded = decode(bytes.toOpenArray(0, hex.len div 2 - 1))
      # Successful decodes report the value and prefix length, allowing the harness to check both.
      if decoded.ok: echo $uint64(decoded.value) & " " & $decoded.consumed
      else:
        # A failed decode has no value; report its typed reason instead.
        # Keep truncation separate from overlong encodings in the shared driver protocol.
        case decoded.error
        # The header or its announced payload is incomplete.
        of truncated: echo "truncated"
        # The representation uses more bytes than the decoded value requires.
        of nonCanonical: echo "noncanonical"
    # Reject a command that is neither encode nor decode.
    else: echo "inputerror"
  except ValueError:
    # Report bad decimal/hex input without terminating the remaining requests.
    echo "inputerror"
