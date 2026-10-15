## GP v0.7.1 C.1/C.2 bounded complete work-report codec; see spec/work-report.md.
import ./[natural, fixed_unsigned, bounded, composite, work_digest]

type
  # Distinct generic hash domains own their bytes and cannot be silently interchanged.
  ReportHash*[kind: static int] = object
    bytes*: array[32, byte]
  # Package identity is separate from roots and historical block identities.
  PackageHash* = ReportHash[0]
  # Erasure commitment identifies the auditable bundle.
  ErasureRoot* = ReportHash[1]
  # Export commitment identifies the segment tree.
  SegmentRoot* = ReportHash[2]
  # Historical anchor identity.
  BlockHash* = ReportHash[3]
  # Posterior state commitment at the anchor.
  StateRoot* = ReportHash[4]
  # Accumulation output log commitment at the anchor.
  AccumulationRoot* = ReportHash[5]
  # Authorization-code identity has a separate nominal domain.
  AuthorizerHash* = ReportHash[6]
  # Serialized auditable-bundle byte count uses E4.
  BundleLength* = distinct uint32
  # Exported segment count uses E2.
  SegmentCount* = distinct uint16
  # Historical lookup timeslot uses E4.
  LookupSlot* = distinct uint32
  # Core indices use general naturals with an explicit chain-dependent upper bound.
  CoreIndex* = distinct uint64
  # Complete owned fixed availability/context fields; prerequisites follow separately on the wire.
  ReportHeader* = object
    packageHash*: PackageHash
    bundleLength*: BundleLength
    erasureRoot*: ErasureRoot
    segmentRoot*: SegmentRoot
    segmentCount*: SegmentCount
    anchor*: BlockHash
    stateRoot*: StateRoot
    accumulationRoot*: AccumulationRoot
    lookupAnchor*: BlockHash
    lookupSlot*: LookupSlot
  # Dictionary entries own their package key and associated segment commitment.
  SegmentLookup* = object
    packageHash*: PackageHash
    segmentRoot*: SegmentRoot
  # Protocol-bounded typed metadata; payload spans explicitly borrow the exact matching input/pool.
  WorkReport* = object
    header*: ReportHeader
    prerequisites*: array[8, PackageHash]
    prerequisiteCount*: int
    core*: CoreIndex
    authorizer*: AuthorizerHash
    authGas*: Gas
    authOutput*: BlobSpan
    lookup*: array[8, SegmentLookup]
    lookupCount*: int
    digests*: array[16, WorkDigest]
    digestCount*: int
  # Success-only report and consumed prefix; default/failed outcomes carry no usable metadata.
  ReportResult* = object
    case error*: CompositeError
    of CompositeError.None:
      # These fields are inaccessible until success is selected.
      value*: WorkReport
      consumed*: int
    else:
      # A malformed final metric cannot expose a partial report.
      discard
  # Fixed header decoding owns all fields and exposes them only after whole-prefix validation.
  ReportHeaderResult* = object
    case error*: CompositeError
    of CompositeError.None:
      # No input references survive this value copy.
      value*: ReportHeader
    else:
      # Missing fixed bytes expose only their reason.
      discard

# Decode all fixed availability/context fields before exposing any owned nominal values.
proc decodeReportHeader*(input: openArray[byte]): ReportHeaderResult {.raises: [].} =
  # Prove every fixed field extent before indexing or narrowing.
  if input.len < 234: return ReportHeaderResult(error: CompositeError.Truncated)
  var value: ReportHeader
  # Copy the complete packageHash into its owned nominal domain.
  for i in 0..<32: value.packageHash.bytes[i] = input[0+i]
  value.bundleLength = BundleLength(decodeFixed(input.toOpenArray(32, 35), ByteWidth(4)).value)
  # Copy the complete erasureRoot into its owned nominal domain.
  for i in 0..<32: value.erasureRoot.bytes[i] = input[36+i]
  # Copy the complete segmentRoot into its owned nominal domain.
  for i in 0..<32: value.segmentRoot.bytes[i] = input[68+i]
  value.segmentCount = SegmentCount(decodeFixed(input.toOpenArray(100, 101), ByteWidth(2)).value)
  # Copy the complete anchor into its owned nominal domain.
  for i in 0..<32: value.anchor.bytes[i] = input[102+i]
  # Copy the complete stateRoot into its owned nominal domain.
  for i in 0..<32: value.stateRoot.bytes[i] = input[134+i]
  # Copy the complete accumulationRoot into its owned nominal domain.
  for i in 0..<32: value.accumulationRoot.bytes[i] = input[166+i]
  # Copy the complete lookupAnchor into its owned nominal domain.
  for i in 0..<32: value.lookupAnchor.bytes[i] = input[198+i]
  value.lookupSlot = LookupSlot(decodeFixed(input.toOpenArray(230, 233), ByteWidth(4)).value)
  ReportHeaderResult(error: CompositeError.None, value: value)

# Emit a fixed header value snapshot atomically, without retaining caller references.
proc encodeReportHeader*(source: ReportHeader, output: var openArray[
    byte]): CompositeWrite {.raises: [].} =
  let value = source
  # Whole-header capacity is required before writing the first hash byte.
  if output.len < 234: return CompositeWrite(error: CompositeError.OutputTooSmall)
  # Preserve packageHash identity order without reversal or implicit hashing.
  for i in 0..<32: output[0+i] = value.packageHash.bytes[i]
  let bundleLength = encodeFixed(FixedUnsigned(value.bundleLength), ByteWidth(4))
  # The nominal width proves each byte belongs to the preflighted fixed header.
  for i in 0..<4: output[32+i] = bundleLength.encoded.bytes[i]
  # Preserve erasureRoot identity order without reversal or implicit hashing.
  for i in 0..<32: output[36+i] = value.erasureRoot.bytes[i]
  # Preserve segmentRoot identity order without reversal or implicit hashing.
  for i in 0..<32: output[68+i] = value.segmentRoot.bytes[i]
  let segmentCount = encodeFixed(FixedUnsigned(value.segmentCount), ByteWidth(2))
  # The nominal width proves each byte belongs to the preflighted fixed header.
  for i in 0..<2: output[100+i] = segmentCount.encoded.bytes[i]
  # Preserve anchor identity order without reversal or implicit hashing.
  for i in 0..<32: output[102+i] = value.anchor.bytes[i]
  # Preserve stateRoot identity order without reversal or implicit hashing.
  for i in 0..<32: output[134+i] = value.stateRoot.bytes[i]
  # Preserve accumulationRoot identity order without reversal or implicit hashing.
  for i in 0..<32: output[166+i] = value.accumulationRoot.bytes[i]
  # Preserve lookupAnchor identity order without reversal or implicit hashing.
  for i in 0..<32: output[198+i] = value.lookupAnchor.bytes[i]
  let lookupSlot = encodeFixed(FixedUnsigned(value.lookupSlot), ByteWidth(4))
  # The nominal width proves each byte belongs to the preflighted fixed header.
  for i in 0..<4: output[230+i] = lookupSlot.encoded.bytes[i]
  CompositeWrite(error: CompositeError.None, written: 234)

# Compare package hash bytes lexicographically; equality is not strict order and therefore rejects duplicates.
proc reportHashLess(a, b: PackageHash): bool {.raises: [].} =
  # Host integer endianness must never affect canonical set or dictionary order.
  for i in 0..<32:
    # The first unequal octet decides order; identical hashes fall through to false.
    if a.bytes[i] != b.bytes[i]: return a.bytes[i] < b.bytes[i]
  false

# Decode one bounded complete report prefix without allocation; spans use original whole-input coordinates.
proc decodeReportBorrowed*(input: openArray[byte], coreCount: uint64): ReportResult {.raises: [].} =
  let header = decodeReportHeader(input)
  # A missing fixed header cannot construct a report with invented default fields.
  if header.error != CompositeError.None: return ReportResult(error: header.error)
  var value = WorkReport(header: header.value)
  var cursor = 234
  # Read a canonical natural into private parser state, never into a caller-visible partial report.
  template readNumber(target: untyped) =
    block:
      let parsed = natural.decode(input.toOpenArray(cursor, input.high))
      # Preserve precise natural failure before advancing or narrowing an attacker-supplied count.
      if not parsed.ok:
        return ReportResult(error: if parsed.error ==
            natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
      target = uint64(parsed.value)
      cursor += parsed.consumed
  var count: uint64
  readNumber(count)
  # Protocol count policy precedes the fixed-stride extent proof and narrowing to a host index.
  if count > 8: return ReportResult(error: CompositeError.LimitExceeded)
  if count > uint64((input.len-cursor) div 32): return ReportResult(error: CompositeError.Truncated)
  value.prerequisiteCount = int(count)
  # Prerequisites form an ordered unique set; received metadata is never silently sorted.
  for i in 0..<value.prerequisiteCount:
    # The complete fixed-stride extent was checked before entering this loop.
    for j in 0..<32: value.prerequisites[i].bytes[j] = input[cursor+j]
    cursor += 32
    # Duplicate and descending set members are equally noncanonical.
    if i > 0 and not reportHashLess(value.prerequisites[i-1], value.prerequisites[i]):
      return ReportResult(error: CompositeError.NonCanonical)
  readNumber(count)
  value.core = CoreIndex(count)
  # Core bounds come from explicit chain configuration, not inferred from available input bytes.
  if count >= coreCount: return ReportResult(error: CompositeError.LimitExceeded)
  if input.len-cursor < 32: return ReportResult(error: CompositeError.Truncated)
  # Authorizer identity is an owned copy rather than an input-buffer view.
  for i in 0..<32: value.authorizer.bytes[i] = input[cursor+i]
  cursor += 32
  readNumber(count)
  value.authGas = Gas(count)
  let auth = decodeBytesBorrowed(input.toOpenArray(cursor, input.high), ByteLimit(49152))
  # Authorization payload length/policy/extent must validate before binding its descriptor.
  if auth.error != ContainerError.None:
    return ReportResult(error: if auth.error == ContainerError.Truncated: CompositeError.Truncated elif auth.error ==
        ContainerError.NonCanonical: CompositeError.NonCanonical else: CompositeError.LimitExceeded)
  value.authOutput = BlobSpan(offset: cursor+auth.offset, length: auth.length)
  cursor += auth.consumed
  var total = value.authOutput.length
  readNumber(count)
  # Lookup keys and prerequisites share one eight-entry dependency budget.
  if count > uint64(8-value.prerequisiteCount): return ReportResult(
      error: CompositeError.LimitExceeded)
  if count > uint64((input.len-cursor) div 64): return ReportResult(error: CompositeError.Truncated)
  value.lookupCount = int(count)
  # Complete key/root pairs retain identity bytes and canonical package-key order.
  for i in 0..<value.lookupCount:
    # Both hashes fit the already checked fixed-stride dictionary extent.
    for j in 0..<32:
      value.lookup[i].packageHash.bytes[j] = input[cursor+j]
      value.lookup[i].segmentRoot.bytes[j] = input[cursor+32+j]
    cursor += 64
    # Equal keys are invalid even if their associated roots differ.
    if i > 0 and not reportHashLess(value.lookup[i-1].packageHash, value.lookup[i].packageHash):
      return ReportResult(error: CompositeError.NonCanonical)
  readNumber(count)
  # Counts cannot index fixed digest capacity before this protocol-bound proof.
  if count < 1 or count > 16: return ReportResult(error: CompositeError.LimitExceeded)
  value.digestCount = int(count)
  # Every child, including its final metric, must validate before any successful report is returned.
  for i in 0..<value.digestCount:
    let parsed = decodeDigestBorrowed(input.toOpenArray(cursor, input.high), ByteLimit(49152-total))
    # Preserve exact nested failures, including the remaining aggregate blob budget.
    if parsed.error != CompositeError.None: return ReportResult(error: parsed.error)
    var digest = parsed.value
    # Successful payloads alone consume aggregate budget and need whole-input coordinates.
    if digest.output.kind == WorkKind.Success:
      total += digest.output.blob.length
      digest.output.blob.offset += cursor
    value.digests[i] = digest
    cursor += parsed.consumed
  ReportResult(error: CompositeError.None, value: value, consumed: cursor)

# Preflight counts, key ordering, every nested descriptor and total blob budget before encoding can mutate output.
proc measureReportBorrowed*(value: WorkReport, poolSize: int,
    coreCount: uint64): CompositeWrite {.raises: [].} =
  # Signed public counts must fit bounded metadata before any array indexing or multiplication.
  if value.prerequisiteCount < 0 or value.prerequisiteCount > 8 or value.lookupCount < 0 or
      value.lookupCount > 8 or value.lookupCount > 8-value.prerequisiteCount or value.digestCount <
      1 or value.digestCount > 16 or uint64(value.core) >= coreCount:
    return CompositeWrite(error: CompositeError.LimitExceeded)
  let span = value.authOutput
  # Subtraction proves endpoint arithmetic, including an empty span at the pool end.
  if span.offset < 0 or span.length < 0 or span.offset > poolSize or span.length >
      poolSize-span.offset:
    return CompositeWrite(error: CompositeError.InvalidSpan)
  var total = span.length
  if total > 49152: return CompositeWrite(error: CompositeError.LimitExceeded)
  # Encoders require canonical ordered input instead of silently sorting caller metadata.
  for i in 1..<value.prerequisiteCount:
    if not reportHashLess(value.prerequisites[i-1], value.prerequisites[i]):
      return CompositeWrite(error: CompositeError.NonCanonical)
  # Only dictionary package keys decide ordering and uniqueness.
  for i in 1..<value.lookupCount:
    if not reportHashLess(value.lookup[i-1].packageHash, value.lookup[i].packageHash):
      return CompositeWrite(error: CompositeError.NonCanonical)
  var required = 234 + natural.encode(JamNatural(value.prerequisiteCount)).len +
      32*value.prerequisiteCount + natural.encode(JamNatural(value.core)).len + 32 + natural.encode(
      JamNatural(value.authGas)).len + natural.encode(JamNatural(total)).len + total +
      natural.encode(JamNatural(value.lookupCount)).len + 64*value.lookupCount + natural.encode(
      JamNatural(value.digestCount)).len
  # Validate the last digest before any earlier header or authorization bytes can be written.
  for i in 0..<value.digestCount:
    let digest = value.digests[i]
    let measured = measureWork(digest.output, poolSize, ByteLimit(49152-total))
    if measured.error != CompositeError.None: return measured # Exact work/tag/span error propagation.
    if digest.output.kind == WorkKind.Success: total +=
        digest.output.blob.length # Error variants have no blob budget.
    var size = 76+measured.written
    let numbers = [uint64(digest.refine.gasUsed), uint64(digest.refine.imports), uint64(
        digest.refine.extrinsicCount), uint64(digest.refine.extrinsicSize), uint64(
        digest.refine.exports)]
    # Each of the five bounded naturals contributes its canonical wire width.
    for number in numbers: size += natural.encode(JamNatural(number)).len
    # Subtraction protects host addition even on narrower address spaces.
    if size > high(int)-required: return CompositeWrite(error: CompositeError.LengthOverflow)
    required += size
  CompositeWrite(error: CompositeError.None, written: required)

# Commit one canonical natural into a proven complete destination extent; no allocations are required.
proc reportPutNatural(number: uint64, output: var openArray[byte], cursor: var int) {.raises: [].} =
  let encoded = natural.encode(JamNatural(number))
  # All target bytes belong to the enclosing encoder's preflighted extent.
  for i in 0..<encoded.len: output[cursor+i] = encoded.bytes[i]
  cursor += encoded.len

# Encode a value snapshot atomically, preserving the entire borrowed pool against overlap.
proc encodeReportBorrowed*(source: WorkReport, pool: openArray[byte], coreCount: uint64,
    output: var openArray[byte]): CompositeWrite {.raises: [].} =
  let value = source
  let measured = measureReportBorrowed(value, pool.len, coreCount)
  # No mutation is permitted until all fixed fields and the final nested metric have validated.
  if measured.error != CompositeError.None: return measured
  let required = measured.written
  if output.len < required: return CompositeWrite(error: CompositeError.OutputTooSmall)
  # Compare address differences without overflowing pointer-end arithmetic; empty pools do not alias.
  if pool.len > 0:
    let a = cast[uint](unsafeAddr pool[0])
    let b = cast[uint](addr output[0])
    if (a <= b and b-a < uint(pool.len)) or (b < a and a-b < uint(required)):
      return CompositeWrite(error: CompositeError.AliasedBuffers)
  discard encodeReportHeader(value.header, output.toOpenArray(0, 233))
  var cursor = 234
  reportPutNatural(uint64(value.prerequisiteCount), output, cursor)
  # Commit ordered prerequisite hashes without mutating caller metadata.
  for i in 0..<value.prerequisiteCount:
    for j in 0..<32: output[cursor+j] = value.prerequisites[i].bytes[j] # Whole hash extent is preflighted.
    cursor += 32
  reportPutNatural(uint64(value.core), output, cursor)
  # Authorizer identity has no implicit hashing or byte reversal.
  for i in 0..<32: output[cursor+i] = value.authorizer.bytes[i]
  cursor += 32
  reportPutNatural(uint64(value.authGas), output, cursor)
  reportPutNatural(uint64(value.authOutput.length), output, cursor)
  # Stable disjoint spans permit the same standard bulk copy used by the existing byte codec.
  if value.authOutput.length > 0:
    copyMem(addr output[cursor], unsafeAddr pool[value.authOutput.offset], value.authOutput.length)
  cursor += value.authOutput.length
  reportPutNatural(uint64(value.lookupCount), output, cursor)
  # Commit complete dictionary pairs only after every key and descriptor is validated.
  for i in 0..<value.lookupCount:
    for j in 0..<32:
      # Both fixed hashes lie inside the proven complete destination extent.
      output[cursor+j] = value.lookup[i].packageHash.bytes[j]
      output[cursor+32+j] = value.lookup[i].segmentRoot.bytes[j]
    cursor += 64
  reportPutNatural(uint64(value.digestCount), output, cursor)
  # Child result guards remain enabled; enclosing preflight has proved that each encode succeeds.
  for i in 0..<value.digestCount:
    let encoded = encodeDigestBorrowed(value.digests[i], pool, ByteLimit(49152), output.toOpenArray(
        cursor, required-1))
    doAssert encoded.error == CompositeError.None
    cursor += encoded.written
  CompositeWrite(error: CompositeError.None, written: cursor)
