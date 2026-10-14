## Trusted local adapter for complete work-digest encoding and decoding.
import std/[os, strutils]
import ./ownership_checks
import ../src/[composite, bounded, work_digest]

# Decode bounded adapter hex, allocating only for the actual trusted request text.
proc parseBytes(text: string): seq[byte] =
  # A dash represents an empty payload, keeping every request token explicit.

  if text == "-": return @[]
  # Reject incomplete pairs and requests beyond this adapter's 32 KiB capacity.

  if text.len mod 2 != 0 or text.len > 65536: raise newException(ValueError, "hex length")
  result = newSeq[byte](text.len div 2)
  # Validate the alphabet before converting each pair into a byte.

  for i in 0..<result.len:
    let pair = text[i * 2..i * 2 + 1]
    for c in pair:
      # Only lowercase hex belongs to this test protocol.

      if c notin {'0'..'9', 'a'..'f'}: raise newException(ValueError, "hex digit")
    result[i] = byte(parseHexInt(pair))

# Print actual encoded or decoded payload bytes; dash denotes an empty payload.
proc hexText(bytes: openArray[byte]): string =
  # Empty blobs need an explicit token before the reported consumed length.

  if bytes.len == 0: return "-"
  result = ""
  # Convert exactly the passed span rather than unused caller-owned storage.

  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

# Parse a bounded output capacity rather than letting textual requests choose arbitrary allocations.
proc capacity(text: string, maximum: int): int =
  result = parseInt(text)
  # Adapter bounds differ from production resource limits and guard only test utility storage.

  if result < 0 or result > maximum: raise newException(ValueError, "capacity")

# Print every decoded field, allowing the independent oracle to check more than round-trip identity.
proc digestText(value: WorkDigest, wire: openArray[byte], consumed: int): string =
  var payload = "-"
  # Only success has a borrowed blob in the original full input.
  if value.output.kind == WorkKind.Success:
    let span = value.output.blob
    payload = hexText(wire.toOpenArray(span.offset, span.offset + span.length - 1))
  result = $uint32(value.service) & " " & hexText(array[32, byte](value.codeHash)) & " " &
      hexText(array[32, byte](value.payloadHash)) & " " & $uint64(value.accumulateGas) & " " &
      $ord(value.output.kind) & " " & payload & " " & $uint64(value.refine.gasUsed) & " " &
      $uint64(value.refine.imports) & " " & $uint64(value.refine.extrinsicCount) & " " &
      $uint64(value.refine.extrinsicSize) & " " & $uint64(value.refine.exports) & " " & $consumed

# Read trusted local request text; utility allocations are separate from the allocation-free production codec.
for line in readFile(paramStr(1)).splitLines():
  # File-final newline does not describe a codec request.
  if line.len == 0: continue
  try:
    let p = line.split(' ')
    var output = newSeq[byte](32768)
    # Detect mutation anywhere in the encoder destination, including unused bytes.
    for b in output.mitems: b = 77
    # Encoder input supplies all ten fields explicitly, with typed construction after parsing.
    if p.len == 14 and p[0] == "E":
      let limit = ByteLimit(parseBiggestUInt(p[1]))
      let cap = capacity(p[2], output.len)
      let service = parseBiggestUInt(p[3])
      let code = parseBytes(p[4])
      let payloadHash = parseBytes(p[5])
      let gas = parseBiggestUInt(p[6])
      let tag = parseInt(p[7])
      let pool = parseBytes(p[8])
      # Reject textual narrowing or incorrectly sized fixed hashes before constructing public fields.
      if service > high(uint32) or code.len != 32 or payloadHash.len != 32 or tag < 0 or tag > 6:
        raise newException(ValueError, "field")
      var c, h: array[32, byte]
      # Copy the checked exact hash lengths into nominal owned storage.
      for i in 0..<32: c[i] = code[i]; h[i] = payloadHash[i]
      let work = if tag == 0: WorkOutput(kind: WorkKind.Success, blob: BlobSpan(offset: 0,
          length: pool.len)) else: WorkOutput(kind: WorkKind(tag))
      let value = WorkDigest(service: ServiceIndex(uint32(service)), codeHash: CodeHash(c),
          payloadHash: PayloadHash(h), accumulateGas: Gas(gas), output: work, refine: RefineLoad(
              gasUsed: Gas(parseBiggestUInt(p[9])),
          imports: ImportCount(parseBiggestUInt(p[10])), extrinsicCount: ExtrinsicCount(
              parseBiggestUInt(p[11])),
          extrinsicSize: ExtrinsicBytes(parseBiggestUInt(p[12])), exports: ExportCount(
              parseBiggestUInt(p[13]))))
      let written = encodeDigestBorrowed(value, pool, limit, output.toOpenArray(0, cap - 1))
      # Only completed encodes expose bytes; failures preserve the entire sentinel destination.
      if written.error == CompositeError.None: echo hexText(output.toOpenArray(0, written.written - 1))
      else:
        for b in output: doAssert b == 77 # A late suffix failure must not commit the fixed prefix.
        echo ($written.error).toLowerAscii()
    elif p.len == 3 and p[0] == "D":
      # Every decoded fixed field and metric is printed; successful blobs are read from the retained original input.
      let limit = ByteLimit(parseBiggestUInt(p[1]))
      let wire = parseBytes(p[2])
      let parsed = decodeDigestBorrowed(wire, limit)
      if parsed.error != CompositeError.None:
        echo ($parsed.error).toLowerAscii() # No usable digest on invalid input.
      else:
        # Exercise owned fixed fields, metrics and output against every full digest vector.
        checkOwnedDigest(wire, limit, parsed)
        let encoded = encodeDigestBorrowed(parsed.value, wire, limit, output)
        doAssert encoded.error == CompositeError.None and encoded.written == parsed.consumed
        # Confirm native reconstruction of the consumed prefix without unrelated trailing data.
        for i in 0..<parsed.consumed: doAssert output[i] == wire[i]
        echo digestText(parsed.value, wire, parsed.consumed)
    else:
      echo "inputerror" # Unknown operations or missing/extra fields are malformed trusted requests.
  except ValueError:
    echo "inputerror" # Adapter parse errors must not be mistaken for production codec errors.
