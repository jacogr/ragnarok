## Trusted local adapters for optional/work variants and complete nested preimages.
import std/[assertions, cmdline, strutils, syncio]
import ./batch_support
import ../support/ownership_checks
import ../../src/codec/[composite, bounded]

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

# Verify exact encode/decode correspondence using a separate destination, never aliasing the retained wire pool.
proc samePrefix(wire: openArray[byte], encoded: CompositeWrite, output: openArray[byte],
    consumed: int) =
  assert encoded.error == CompositeError.None and encoded.written == consumed
  # Check every tag, tuple field and nested length.
  for i in 0..<consumed: assert wire[i] == output[i]

# Decode/encode trusted batches, with independent destination sentinels for every native failed operation.
try:
  for line in readFile(paramStr(1)).splitLines():
    # File-final newline is not a request.
    if line.len == 0: continue
    let p = line.split(' ')
    var bytes = newSeq[byte](32768)
    # Failed encodes must not commit even a header.
    for b in bytes.mitems: b = 77
    if p.len == 5 and p[0] in ["OE", "WE"]:
      # Checked textual tags select a typed optional/variant; binary discriminators are tested via decoder commands.

      let tag = integer(p[1])
      let limit = ByteLimit(unsigned(p[2]))
      let cap = capacity(p[3], bytes.len)
      let pool = parseBytes(p[4])
      let span = BlobSpan(offset: 0, length: pool.len)
      var encoded = default(CompositeWrite)
      if p[0] == "OE":
        # A bool input has only these states.
        if tag notin [0, 1]: assert false, "presence"
        let value = if tag == 0: absentBlob() else: presentBlob(span)
        encoded = encodeOptionalBorrowed(value, pool, limit, bytes.toOpenArray(0, cap - 1))
      else:
        # Reject textual enum values before casting; unknown binary variants go through decodeWorkBorrowed instead.

        if tag < 0 or tag > 6: echo "invalidtag"; continue
        let value = if tag == 0: successfulWork(span) else: failedWork(WorkKind(tag))
        encoded = encodeWorkBorrowed(value, pool, limit, bytes.toOpenArray(0, cap - 1))
      # Actual completed bytes.
      if encoded.error == CompositeError.None: echo hexText(bytes.toOpenArray(0, encoded.written - 1))
      else:
        # Whole destination unchanged on failure.
        for b in bytes: assert b == 77
        echo ($encoded.error).toLowerAscii()
    elif p.len == 3 and p[0] in ["OD", "WD"]:
      # Views point into this retained local wire buffer; re-encoding uses separate caller-owned storage.

      let limit = ByteLimit(unsigned(p[1]))
      let wire = parseBytes(p[2])
      if p[0] == "OD":
        let decoded = decodeOptionalBorrowed(wire, limit)
        # No usable view.
        if decoded.error != CompositeError.None: echo ($decoded.error).toLowerAscii(); continue
        # Verify owned optional metadata and bytes on the same conformance input.
        checkOwnedOptional(wire, limit, decoded)
        samePrefix(wire, encodeOptionalBorrowed(decoded.value, wire, limit, bytes), bytes,
            decoded.consumed)
        if decoded.value.present:
          let span = decoded.value.blob
          echo "present:" & hexText(wire.toOpenArray(span.offset, span.offset + span.length - 1)) &
              " " & $decoded.consumed
        # No payload belongs to absence.
        else: echo "absent " & $decoded.consumed
      else:
        let decoded = decodeWorkBorrowed(wire, limit)
        # No active union on bad wire.
        if decoded.error != CompositeError.None: echo ($decoded.error).toLowerAscii(); continue
        # Verify both owned work alternatives against independently checked responses.
        checkOwnedWork(wire, limit, decoded)
        samePrefix(wire, encodeWorkBorrowed(decoded.value, wire, limit, bytes), bytes,
            decoded.consumed)
        var payload = "-"
        if decoded.value.kind == WorkKind.Success:
          let span = decoded.value.blob
          # Only success has bytes.
          payload = hexText(wire.toOpenArray(span.offset, span.offset + span.length - 1))
        echo $ord(decoded.value.kind) & ":" & payload & " " & $decoded.consumed
    elif p.len == 6 and p[0] in ["PE", "PD"]:
      # Outer, per-blob and aggregate ceilings are separate explicit policies.

      let limits = PreimageLimits(items: ElementLimit(unsigned(p[1])),
        perBlob: ByteLimit(unsigned(p[2])),
        totalBlobBytes: ByteLimit(unsigned(p[3])))
      if p[0] == "PE":
        var records: seq[Preimage] = @[]
        var pool: seq[byte] = @[]
        if p[5] != "-":
          # A trusted record list uses service:payload tuples; each checked ID must fit its nominal uint32 domain.

          for text in p[5].split(';'):
            let pair = text.split(':')
            # Adapter resource bound.
            if pair.len != 2 or records.len >= 256: assert false, "records"
            let service = unsigned(pair[0])
            # No silent nominal narrowing.
            if service > high(uint32): assert false, "service"
            let payload = parseBytes(pair[1])
            # Bound actual utility storage.
            if payload.len > 32768 - pool.len: assert false, "pool"
            records.add(Preimage(service: ServiceIndex(uint32(service)), blob: BlobSpan(
                offset: pool.len, length: payload.len)))
            # Append actual payload octets; the nightly exposes element-wise sequence insertion.
            for b in payload: pool.add(b)
        let cap = capacity(p[4], bytes.len)
        let encoded = encodePreimagesBorrowed(records, pool, limits, bytes.toOpenArray(0, cap - 1))
        # Full extrinsic frame.
        if encoded.error == CompositeError.None: echo hexText(bytes.toOpenArray(0, encoded.written - 1))
        else:
          # All late record errors must preserve output.
          for b in bytes: assert b == 77
          echo ($encoded.error).toLowerAscii()
      else:
        let wire = parseBytes(p[5])
        var records = newSeq[Preimage](capacity(p[4], 256))
        # Sentinels.
        for item in records.mitems: item = Preimage(service: ServiceIndex(999), blob: BlobSpan(
            offset: 333, length: 444))
        let decoded = decodePreimagesBorrowed(wire, limits, records)
        if decoded.error != CompositeError.None:
          # Atomic failure.
          for item in records: assert uint32(item.service) == 999 and item.blob.offset == 333 and
              item.blob.length == 444
          echo ($decoded.error).toLowerAscii()
          continue
        # Verify owned service IDs, all nested blobs and the complete canonical frame.
        checkOwnedPreimages(wire, limits, decoded, records)
        samePrefix(wire, encodePreimagesBorrowed(records.toOpenArray(0, decoded.count - 1), wire,
            limits, bytes), bytes, decoded.consumed)
        var fields: seq[string] = @[]
        for i in 0..<decoded.count:
          # Report actual decoded tuple values, not merely a matching re-encoded byte stream.

          let span = records[i].blob
          fields.add($uint32(records[i].service) & ":" & hexText(wire.toOpenArray(span.offset,
              span.offset + span.length - 1)))
        echo (if fields.len == 0: "-" else: fields.join(";")) & " " & $decoded.consumed
    # Wrong command/token count never reaches a production API.
    else: echo "inputerror"
except:
  # Fixture I/O failures are fatal and cannot masquerade as production codec errors.
  quit 2
