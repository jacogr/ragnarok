## Trusted local adapter for complete work-digest encoding and decoding.
import std/[os, strutils]
import ./report_check
import ../../src/codec/[composite, bounded, work_digest, work_report, report_owned, owned]

# Decode bounded adapter hex, allocating only for the actual trusted request text.
proc parseBytes(text: string): seq[byte] =
  # A dash represents an empty payload, keeping every request token explicit.

  if text == "-": return @[]
  # Reject incomplete pairs and requests beyond this adapter's 64 KiB capacity.

  if text.len mod 2 != 0 or text.len > 131072: raise newException(ValueError, "hex length")
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

# Render declared fixed fields independently of the production header encoder, detecting field swaps.
proc headerBytes(value: ReportHeader): array[272, byte] =
  # Inspect packageHash directly, independently of production field ordering.
  for i in 0..<32: result[0+i] = value.packageHash.bytes[i]
  # Inspect bundleLength directly, independently of production field ordering.
  for i in 0..<4: result[32+i] = byte((uint64(value.bundleLength) shr (8*i)) and 255)
  # Inspect erasureRoot directly, independently of production field ordering.
  for i in 0..<32: result[36+i] = value.erasureRoot.bytes[i]
  # Inspect erasureShards directly, independently of production field ordering.
  for i in 0..<2: result[68+i] = byte((uint64(value.erasureShards) shr (8*i)) and 255)
  # Inspect segmentRoot directly, independently of production field ordering.
  for i in 0..<32: result[70+i] = value.segmentRoot.bytes[i]
  # Inspect segmentCount directly, independently of production field ordering.
  for i in 0..<2: result[102+i] = byte((uint64(value.segmentCount) shr (8*i)) and 255)
  # Inspect anchor directly, independently of production field ordering.
  for i in 0..<32: result[104+i] = value.anchor.bytes[i]
  # Inspect anchorSlot directly, independently of production field ordering.
  for i in 0..<4: result[136+i] = byte((uint64(value.anchorSlot) shr (8*i)) and 255)
  # Inspect stateRoot directly, independently of production field ordering.
  for i in 0..<32: result[140+i] = value.stateRoot.bytes[i]
  # Inspect accumulationRoot directly, independently of production field ordering.
  for i in 0..<32: result[172+i] = value.accumulationRoot.bytes[i]
  # Inspect lookupAnchor directly, independently of production field ordering.
  for i in 0..<32: result[204+i] = value.lookupAnchor.bytes[i]
  # Inspect lookupSlot directly, independently of production field ordering.
  for i in 0..<4: result[236+i] = byte((uint64(value.lookupSlot) shr (8*i)) and 255)
  # Inspect lookupStateRoot directly, independently of production field ordering.
  for i in 0..<32: result[240+i] = value.lookupStateRoot.bytes[i]

# Build fixed fields independently, including invalid shard counts for encoder rejection probes.
proc headerValue(fixed: openArray[byte]): ReportHeader =
  doAssert fixed.len == 272
  # Retain every packageHash byte in its exact nominal destination.
  for i in 0..<32: result.packageHash.bytes[i] = fixed[0+i]
  var bundleLength = 0'u64
  # Read the trusted adapter's fixed-width bundleLength independently.
  for i in 0..<4: bundleLength = bundleLength or (uint64(fixed[32+i]) shl (8*i))
  result.bundleLength = BundleLength(bundleLength)
  # Retain every erasureRoot byte in its exact nominal destination.
  for i in 0..<32: result.erasureRoot.bytes[i] = fixed[36+i]
  var erasureShards = 0'u64
  # Read the trusted adapter's fixed-width erasureShards independently.
  for i in 0..<2: erasureShards = erasureShards or (uint64(fixed[68+i]) shl (8*i))
  result.erasureShards = ErasureShards(erasureShards)
  # Retain every segmentRoot byte in its exact nominal destination.
  for i in 0..<32: result.segmentRoot.bytes[i] = fixed[70+i]
  var segmentCount = 0'u64
  # Read the trusted adapter's fixed-width segmentCount independently.
  for i in 0..<2: segmentCount = segmentCount or (uint64(fixed[102+i]) shl (8*i))
  result.segmentCount = SegmentCount(segmentCount)
  # Retain every anchor byte in its exact nominal destination.
  for i in 0..<32: result.anchor.bytes[i] = fixed[104+i]
  var anchorSlot = 0'u64
  # Read the trusted adapter's fixed-width anchorSlot independently.
  for i in 0..<4: anchorSlot = anchorSlot or (uint64(fixed[136+i]) shl (8*i))
  result.anchorSlot = AnchorSlot(anchorSlot)
  # Retain every stateRoot byte in its exact nominal destination.
  for i in 0..<32: result.stateRoot.bytes[i] = fixed[140+i]
  # Retain every accumulationRoot byte in its exact nominal destination.
  for i in 0..<32: result.accumulationRoot.bytes[i] = fixed[172+i]
  # Retain every lookupAnchor byte in its exact nominal destination.
  for i in 0..<32: result.lookupAnchor.bytes[i] = fixed[204+i]
  var lookupSlot = 0'u64
  # Read the trusted adapter's fixed-width lookupSlot independently.
  for i in 0..<4: lookupSlot = lookupSlot or (uint64(fixed[236+i]) shl (8*i))
  result.lookupSlot = LookupSlot(lookupSlot)
  # Retain every lookupStateRoot byte in its exact nominal destination.
  for i in 0..<32: result.lookupStateRoot.bytes[i] = fixed[240+i]

# Print every decoded field and full child digests for independent semantic comparison, not round trips alone.
proc printReport(value: WorkReport, wire: openArray[byte], consumed: int) =
  var prerequisites = newSeq[byte](32*value.prerequisiteCount)
  # Ordered prerequisite identities must remain visible, not merely their count.
  for i in 0..<value.prerequisiteCount:
    for j in 0..<32: prerequisites[32*i+j] = value.prerequisites[i].bytes[j] # Complete fixed-stride members.
  var lookup = newSeq[byte](64*value.lookupCount)
  # Print both key and value fields of each canonical dictionary entry.
  for i in 0..<value.lookupCount:
    for j in 0..<32:
      # The independently sized token retains exact pair order and identity bytes.
      lookup[64*i+j] = value.lookup[i].packageHash.bytes[j]
      lookup[64*i+32+j] = value.lookup[i].segmentRoot.bytes[j]
  var digests = newSeq[byte](65536)
  var cursor = 0
  # Existing verified child encoders reconstruct every digest from its typed fields and borrowed payload.
  for i in 0..<value.digestCount:
    let written = encodeDigestBorrowed(value.digests[i], wire, ByteLimit(49152),
        digests.toOpenArray(cursor, digests.high))
    doAssert written.error == CompositeError.None
    cursor += written.written
  echo hexText(headerBytes(value.header)) & " " & hexText(prerequisites) & " " & $uint64(
      value.core) & " " &
    hexText(value.authorizer.bytes) & " " & $uint64(value.authGas) & " " &
    hexText(wire.toOpenArray(value.authOutput.offset,
        value.authOutput.offset+value.authOutput.length-1)) & " " &
    hexText(lookup) & " " & hexText(digests.toOpenArray(0, cursor-1)) & " " & $value.digestCount &
        " " & $consumed

# Construct typed report fields from the independent oracle representation, without using the new report decoder.
proc buildReport(p: seq[string]): tuple[value: WorkReport, pool: seq[byte]] =
  let fixed = parseBytes(p[3])
  doAssert fixed.len == 272
  result.value.header = headerValue(fixed)
  let prerequisites = parseBytes(p[4])
  let authorizer = parseBytes(p[6])
  let auth = parseBytes(p[8])
  let lookup = parseBytes(p[9])
  let digests = parseBytes(p[10])
  doAssert prerequisites.len mod 32 == 0 and prerequisites.len <= 256 and authorizer.len == 32 and
    lookup.len mod 64 == 0 and lookup.len <= 512 and auth.len+digests.len <= 65536
  result.value.prerequisiteCount = prerequisites.len div 32
  result.value.lookupCount = lookup.len div 64
  result.value.core = CoreIndex(parseBiggestUInt(p[5]))
  result.value.authGas = Gas(parseBiggestUInt(p[7]))
  result.value.digestCount = capacity(p[11], 16)
  doAssert result.value.digestCount >= 1
  # Trusted adapter construction still proves exact widths before indexing nominal hash storage.
  for i in 0..<32: result.value.authorizer.bytes[i] = authorizer[i]
  for i in 0..<result.value.prerequisiteCount:
    for j in 0..<32: result.value.prerequisites[i].bytes[j] = prerequisites[
        32*i+j] # Independent set construction.
  for i in 0..<result.value.lookupCount:
    for j in 0..<32:
      # Independent dictionary construction does not call the work-report parser.
      result.value.lookup[i].packageHash.bytes[j] = lookup[64*i+j]
      result.value.lookup[i].segmentRoot.bytes[j] = lookup[64*i+32+j]
  result.pool = newSeq[byte](auth.len+digests.len)
  # Utility storage owns one stable pool for authorization bytes and child wire frames.
  for i in 0..<auth.len: result.pool[i] = auth[i]
  for i in 0..<digests.len: result.pool[auth.len+i] = digests[i]
  result.value.authOutput = BlobSpan(offset: 0, length: auth.len)
  var cursor = auth.len
  # Only existing digest parsing supplies child values; the new report decoder is not an encoding oracle.
  for i in 0..<result.value.digestCount:
    let parsed = decodeDigestBorrowed(result.pool.toOpenArray(cursor, result.pool.high), ByteLimit(49152))
    doAssert parsed.error == CompositeError.None
    var digest = parsed.value
    if digest.output.kind == WorkKind.Success:
      # Each successful payload must refer to the single construction pool, not its child slice.
      digest.output.blob.offset += cursor
    result.value.digests[i] = digest
    cursor += parsed.consumed
  doAssert cursor == result.pool.len

# Retain an ARC alias after the original local result leaves scope, proving automatic owner retention.
proc retainReport(wire: openArray[byte], cores: uint64): OwnedReport =
  let captured = decodeOwnedReport(wire, cores)
  doAssert captured.error == OwnershipError.None
  captured.value

# Check immutable capture and owner-bound extraction after the caller changes its entire input buffer.
proc checkOwner(wire: var seq[byte], value: WorkReport, consumed: int, cores: uint64) =
  let owner = retainReport(wire, cores)
  let info = ownedReportInfo(owner)
  doAssert info.error == OwnershipError.None and info.value.consumed == consumed and
    info.value.digestCount == value.digestCount and uint64(info.value.core) == uint64(
        value.core) and
    uint64(info.value.authGas) == uint64(value.authGas)
  # Copied fixed metadata and dependency identities must retain their declared domains and exact values.
  doAssert headerBytes(info.value.header) == headerBytes(value.header) and
      info.value.authorizer.bytes == value.authorizer.bytes
  doAssert info.value.prerequisiteCount == value.prerequisiteCount and info.value.lookupCount ==
      value.lookupCount
  for i in 0..<value.prerequisiteCount:
    let item = ownedReportPrerequisite(owner, i)
    doAssert item.error == OwnershipError.None and item.value.bytes == value.prerequisites[i].bytes
  for i in 0..<value.lookupCount:
    let item = ownedReportLookup(owner, i)
    doAssert item.error == OwnershipError.None and item.value.packageHash.bytes == value.lookup[
        i].packageHash.bytes and item.value.segmentRoot.bytes == value.lookup[i].segmentRoot.bytes
  for i in 0..<value.digestCount:
    let item = ownedReportDigest(owner, i)
    let expected = value.digests[i]
    doAssert item.error == OwnershipError.None and uint32(item.value.service) == uint32(
        expected.service)
    doAssert array[32, byte](item.value.codeHash) == array[32, byte](expected.codeHash) and array[
        32, byte](item.value.payloadHash) == array[32, byte](expected.payloadHash)
    doAssert uint64(item.value.accumulateGas) == uint64(expected.accumulateGas) and
        item.value.output.kind == expected.output.kind
    if expected.output.kind == WorkKind.Success:
      # Successful metadata exposes only the retained length, not detached pool coordinates.
      doAssert item.value.output.length == expected.output.blob.length
    doAssert uint64(item.value.refine.gasUsed) == uint64(expected.refine.gasUsed) and uint64(
        item.value.refine.imports) == uint64(expected.refine.imports) and uint64(
        item.value.refine.extrinsicCount) == uint64(expected.refine.extrinsicCount) and uint64(
        item.value.refine.extrinsicSize) == uint64(expected.refine.extrinsicSize) and uint64(
        item.value.refine.exports) == uint64(expected.refine.exports)
  doAssert ownedReportPrerequisite(owner, value.prerequisiteCount).error ==
      OwnershipError.InvalidIndex
  doAssert ownedReportLookup(owner, value.lookupCount).error == OwnershipError.InvalidIndex
  doAssert ownedReportDigest(owner, value.digestCount).error == OwnershipError.InvalidIndex
  var missing: OwnedReport
  doAssert ownedReportInfo(missing).error == OwnershipError.InvalidOwner
  var original = newSeq[byte](wire.len)
  # Explicitly copy original expectations; assignment semantics must not hide input aliasing in the test.
  for i in 0..<wire.len: original[i] = wire[i]
  for b in wire.mitems: b = 99 # Mutate hashes, payloads, counts and trailing bytes after capture.
  var output = newSeq[byte](65536)
  let encoded = encodeOwnedReport(owner, output)
  doAssert encoded.error == OwnershipError.None and encoded.value == consumed
  # The owner must retain exact consumed bytes while ignoring unrelated trailing input.
  for i in 0..<consumed: doAssert output[i] == original[i]
  var payload = newSeq[byte](65536)
  # Index zero selects authorization output; following indices select the corresponding digest.
  for index in 0..value.digestCount:
    var blob = value.authOutput
    var hasBlob = true
    if index > 0:
      # Payload-free work errors must reject extraction, not appear as empty successful outputs.
      let digest = value.digests[index-1]
      hasBlob = digest.output.kind == WorkKind.Success
      if hasBlob: blob = digest.output.blob # Select only the active successful descriptor.
    let copied = copyReportBlob(owner, index, payload)
    if hasBlob:
      doAssert copied.error == OwnershipError.None and copied.value == blob.length
      for i in 0..<blob.length: doAssert payload[i] == original[blob.offset+i] # Every retained payload byte.
    else:
      doAssert copied.error == OwnershipError.InvalidIndex # Work errors are valid values with no payload.
  for b in output.mitems: b = 77 # Reinitialize all sentinels for the failing owner encode.
  let small = encodeOwnedReport(owner, output.toOpenArray(0, consumed-2))
  doAssert small.error == OwnershipError.OutputTooSmall
  for b in output: doAssert b == 77 # Capacity failure cannot alter unused destination bytes either.
  doAssert copyReportBlob(owner, -1, payload).error == OwnershipError.InvalidIndex
  # Restore the adapter input for independent field printing and borrowed re-encoding after owner checks.
  for i in 0..<wire.len: wire[i] = original[i]

# Probe late encoder failures and complete-pool overlap, asserting whole-destination atomicity.
proc mutation(kind: string, wire: var seq[byte], cores: uint64) =
  let decoded = decodeReportBorrowed(wire, cores)
  doAssert decoded.error == CompositeError.None
  var value = decoded.value
  var output = newSeq[byte](65536)
  for b in output.mitems: b = 77 # Detect even a speculative first-byte commit.
  case kind
  of "span": value.digests[value.digestCount-1].output = WorkOutput(kind: WorkKind.Success,
      blob: BlobSpan(offset: wire.len, length: 1)) # Invalid final descriptor.
  of "count": value.digestCount = 0 # A report requires at least one work digest.
  of "tag": value.digests[value.digestCount-1].output = WorkOutput(kind: cast[WorkKind](
      255)) # Explicit unsafe enum fabrication must fail preflight.
  of "core": value.core = CoreIndex(cores) # First index outside the configured core set.
  of "alias":
    # Deliberately manufacture aliasing through the public borrowed buffers to test runtime overlap protection.
    var saved = newSeq[byte](wire.len)
    for i in 0..<wire.len: saved[i] = wire[i] # Own independent expected bytes.
    let written = encodeReportBorrowed(value, wire, cores, wire)
    doAssert written.error == CompositeError.AliasedBuffers
    for i in 0..<wire.len: doAssert wire[i] == saved[
        i] # Protect the entire matching pool, not just selected blobs.
    echo ($written.error).toLowerAscii()
    return
  else: doAssert false # Unregistered operations indicate harness drift.
  let encoded = encodeReportBorrowed(value, wire, cores, output)
  doAssert encoded.error != CompositeError.None
  for b in output: doAssert b == 77 # No late error may leave the header partially committed.
  echo ($encoded.error).toLowerAscii()

# Select independent credential checking before reading a conformance request file.
if paramCount() > 0 and paramStr(1) == "check":
  reportFixtureCheck()
  quit(0)

# Read the identical shared trusted batch protocol; production wire decoding runs entirely in native Nim.
for line in readFile(paramStr(1)).splitLines():
  if line.len == 0: continue # The final newline is not a codec request.
  let p = line.split(' ')
  doAssert p.len == 3 or p.len == 4 or p.len == 12
  let cores = uint64(parseBiggestUInt(p[1]))
  if p[0] == "D" and p.len == 3:
    var wire = parseBytes(p[2])
    let parsed = decodeReportBorrowed(wire, cores)
    if parsed.error != CompositeError.None:
      echo ($parsed.error).toLowerAscii() # Failure exposes only its reason.
    else:
      # Success alone enables owner capture, complete field access and exact borrowed re-encoding.
      checkOwner(wire, parsed.value, parsed.consumed, cores)
      var output = newSeq[byte](65536)
      let encoded = encodeReportBorrowed(parsed.value, wire, cores, output)
      doAssert encoded.error == CompositeError.None and encoded.written == parsed.consumed
      for i in 0..<parsed.consumed: doAssert output[i] == wire[i] # Compare the complete consumed prefix.
      printReport(parsed.value, wire, parsed.consumed)
  elif p[0] == "E" and p.len == 12:
    # Construct independent source fields without invoking the new report decoder.
    let built = buildReport(p)
    let cap = capacity(p[2], 65536)
    var output = newSeq[byte](65536)
    for b in output.mitems: b = 77 # Capacity and late-field failures must preserve every byte.
    let encoded = encodeReportBorrowed(built.value, built.pool, cores, output.toOpenArray(0, cap-1))
    if encoded.error == CompositeError.None: echo hexText(output.toOpenArray(0,
        encoded.written-1)) # Completed bytes only.
    else:
      for b in output: doAssert b == 77 # Whole-destination failure atomicity includes unused space.
      echo ($encoded.error).toLowerAscii()
  elif p[0] == "X" and p.len == 4:
    # Registered native misuse probes exercise the encoder contract beyond malformed wire decoding.
    var wire = parseBytes(p[3])
    mutation(p[2], wire, cores)
  else: doAssert false # Trusted protocol drift must not be interpreted as a successful codec operation.
