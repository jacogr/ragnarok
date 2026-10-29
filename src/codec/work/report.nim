# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP v0.8.0 C.1/C.2 bounded complete work-report codec; see spec/work-report.md.
##
## Exposes report header/source/span types, borrowed report codecs, header codecs and report
## size measurement.

import std/assertions
import ../[natural, fixed_unsigned, bounded, composite]
import ./digest as work_digest

type
  ReportHash*[kind: static[int]] = object ## Distinct generic hash domains own their bytes and cannot be silently interchanged.
    bytes*: array[32, byte]
  PackageHash* = ReportHash[0] ## Package identity is separate from roots and historical block identities.
  ErasureRoot* = ReportHash[1] ## Erasure commitment identifies the auditable bundle.
  SegmentRoot* = ReportHash[2] ## Export commitment identifies the segment tree.
  BlockHash* = ReportHash[3] ## Historical anchor identity.
  StateRoot* = ReportHash[4] ## Posterior state commitment at the anchor.
  AccumulationRoot* = ReportHash[5] ## Accumulation output log commitment at the anchor.
  AuthorizerHash* = ReportHash[6] ## Authorization-code identity has a separate nominal domain.
  BundleLength* = distinct uint32 ## Serialized auditable-bundle byte count uses E4.
  ErasureShards* = distinct uint16 ## Total erasure shards identify the assuring validator-set cardinality, encoded as E2.
  AnchorSlot* = distinct uint32 ## Anchor timeslot uses E4 and cannot be substituted for the lookup timeslot.
  LookupStateRoot* = ReportHash[7] ## Lookup-anchor posterior state has its own nominal role.
  SegmentCount* = distinct uint16 ## Exported segment count uses E2.
  LookupSlot* = distinct uint32 ## Historical lookup timeslot uses E4.
  CoreIndex* = distinct uint64 ## Core indices use general naturals with an explicit chain-dependent upper bound.
  ReportHeader* = object ## Complete owned fixed availability/context fields; prerequisites follow separately on the wire.
    packageHash*: PackageHash
    bundleLength*: BundleLength
    erasureRoot*: ErasureRoot
    erasureShards*: ErasureShards
    segmentRoot*: SegmentRoot
    segmentCount*: SegmentCount
    anchor*: BlockHash
    anchorSlot*: AnchorSlot
    stateRoot*: StateRoot
    accumulationRoot*: AccumulationRoot
    lookupAnchor*: BlockHash
    lookupSlot*: LookupSlot
    lookupStateRoot*: LookupStateRoot
  SegmentLookup* = object ## Dictionary entries own their package key and associated segment commitment.
    packageHash*: PackageHash
    segmentRoot*: SegmentRoot
  WorkReport* = object ## Protocol-bounded typed metadata; payload spans explicitly borrow the exact matching input/pool.
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
  ReportResult* = object ## Complete copied report data is private until the success precondition holds.
    case status: CompositeError
    of None:
      # Borrowed payload spans remain bound to the caller's exact input/pool.
      decodedValue: WorkReport
      byteConsumed: int
    else:
      # Failed/default outcomes contain no partial report or cursor progress.
      discard
  ReportHeaderResult* = object ## Fixed headers are copied values; truncated/invalid headers expose only their reason.
    case status: CompositeError
    of None:
      # The complete header includes every 0.8.0 nominal field.
      decodedValue: ReportHeader
    else:
      # Default results remain Uninitialized, distinct from an all-zero header.
      discard

func error*(value: ReportResult): CompositeError =
  ## Read the full-report outcome without permitting retagging.
  value.status
func error*(value: ReportHeaderResult): CompositeError =
  ## Read the fixed-header outcome without exposing a writable discriminator.
  value.status
func value*(value: ReportResult): WorkReport {.inline, requires: value.status ==
    CompositeError.None.} =
  ## Only complete report decoding exposes copied fields and caller-bound spans.
  value.decodedValue
func consumed*(value: ReportResult): int {.inline, requires: value.status == CompositeError.None.} =
  ## Only complete report decoding may advance the input cursor.
  value.byteConsumed
func value*(value: ReportHeaderResult): ReportHeader {.inline, requires: value.status ==
    CompositeError.None.} =
  ## Failed/default fixed headers cannot expose default nominal identities.
  value.decodedValue

# Validate GP 0.8.0 valcount independently of state-dependent active-set equality.
proc validErasureShards(value: ErasureShards): bool {.raises: [].} =
  uint16(value) >= 6 and uint16(value) <= 1023 and uint16(value) mod 3 == 0

proc decodeReportHeader*(input: openArray[byte]): ReportHeaderResult {.raises: [].} =
  ## Decode all fixed availability/context fields before exposing any owned nominal values.
  # Prove the complete 0.8.0 fixed prefix before reading any new or retained field.
  if input.len < 272: return ReportHeaderResult(status: CompositeError.Truncated)
  var value: ReportHeader = default(ReportHeader)
  # Copy packageHash identity bytes into their owned nominal field.
  for i in 0..<32: value.packageHash.bytes[i] = input[0+i]
  value.bundleLength = BundleLength(decodeFixed(input.toOpenArray(32, 35), ByteWidth(4)).value)
  # Copy erasureRoot identity bytes into their owned nominal field.
  for i in 0..<32: value.erasureRoot.bytes[i] = input[36+i]
  value.erasureShards = ErasureShards(decodeFixed(input.toOpenArray(68, 69), ByteWidth(2)).value)
  # Copy segmentRoot identity bytes into their owned nominal field.
  for i in 0..<32: value.segmentRoot.bytes[i] = input[70+i]
  value.segmentCount = SegmentCount(decodeFixed(input.toOpenArray(102, 103), ByteWidth(2)).value)
  # Copy anchor identity bytes into their owned nominal field.
  for i in 0..<32: value.anchor.bytes[i] = input[104+i]
  value.anchorSlot = AnchorSlot(decodeFixed(input.toOpenArray(136, 139), ByteWidth(4)).value)
  # Copy stateRoot identity bytes into their owned nominal field.
  for i in 0..<32: value.stateRoot.bytes[i] = input[140+i]
  # Copy accumulationRoot identity bytes into their owned nominal field.
  for i in 0..<32: value.accumulationRoot.bytes[i] = input[172+i]
  # Copy lookupAnchor identity bytes into their owned nominal field.
  for i in 0..<32: value.lookupAnchor.bytes[i] = input[204+i]
  value.lookupSlot = LookupSlot(decodeFixed(input.toOpenArray(236, 239), ByteWidth(4)).value)
  # Copy lookupStateRoot identity bytes into their owned nominal field.
  for i in 0..<32: value.lookupStateRoot.bytes[i] = input[240+i]
  # Only a protocol-supported validator-set cardinality can describe erasure shards.
  if not validErasureShards(value.erasureShards):
    return ReportHeaderResult(status: CompositeError.LimitExceeded)
  ReportHeaderResult(status: CompositeError.None, decodedValue: value)

proc encodeReportHeader*(source: ReportHeader, output: var openArray[
    byte]): CompositeWrite {.raises: [].} =
  ## Emit a fixed header value snapshot atomically, without retaining caller references.
  let value = source
  # Reject an invalid shard domain before capacity checks or destination mutation.
  if not validErasureShards(value.erasureShards):
    return compositeFailure(CompositeError.LimitExceeded)
  # Whole-header capacity is required before writing the first hash byte.
  if output.len < 272: return compositeFailure(CompositeError.OutputTooSmall)
  # Preserve the supplied packageHash identity without reversal or hashing.
  for i in 0..<32: output[0+i] = value.packageHash.bytes[i]
  let bundleLength = encodeFixed(FixedUnsigned(value.bundleLength), ByteWidth(4))
  # Commit the preflighted fixed-width bundleLength without narrowing caller data.
  for i in 0..<4: output[32+i] = bundleLength.encoded.bytes[i]
  # Preserve the supplied erasureRoot identity without reversal or hashing.
  for i in 0..<32: output[36+i] = value.erasureRoot.bytes[i]
  let erasureShards = encodeFixed(FixedUnsigned(value.erasureShards), ByteWidth(2))
  # Commit the preflighted fixed-width erasureShards without narrowing caller data.
  for i in 0..<2: output[68+i] = erasureShards.encoded.bytes[i]
  # Preserve the supplied segmentRoot identity without reversal or hashing.
  for i in 0..<32: output[70+i] = value.segmentRoot.bytes[i]
  let segmentCount = encodeFixed(FixedUnsigned(value.segmentCount), ByteWidth(2))
  # Commit the preflighted fixed-width segmentCount without narrowing caller data.
  for i in 0..<2: output[102+i] = segmentCount.encoded.bytes[i]
  # Preserve the supplied anchor identity without reversal or hashing.
  for i in 0..<32: output[104+i] = value.anchor.bytes[i]
  let anchorSlot = encodeFixed(FixedUnsigned(value.anchorSlot), ByteWidth(4))
  # Commit the preflighted fixed-width anchorSlot without narrowing caller data.
  for i in 0..<4: output[136+i] = anchorSlot.encoded.bytes[i]
  # Preserve the supplied stateRoot identity without reversal or hashing.
  for i in 0..<32: output[140+i] = value.stateRoot.bytes[i]
  # Preserve the supplied accumulationRoot identity without reversal or hashing.
  for i in 0..<32: output[172+i] = value.accumulationRoot.bytes[i]
  # Preserve the supplied lookupAnchor identity without reversal or hashing.
  for i in 0..<32: output[204+i] = value.lookupAnchor.bytes[i]
  let lookupSlot = encodeFixed(FixedUnsigned(value.lookupSlot), ByteWidth(4))
  # Commit the preflighted fixed-width lookupSlot without narrowing caller data.
  for i in 0..<4: output[236+i] = lookupSlot.encoded.bytes[i]
  # Preserve the supplied lookupStateRoot identity without reversal or hashing.
  for i in 0..<32: output[240+i] = value.lookupStateRoot.bytes[i]
  compositeWritten(272)

# Compare package hash bytes lexicographically; equality is not strict order and therefore rejects duplicates.
proc reportHashLess(a, b: PackageHash): bool {.raises: [].} =
  # Host integer endianness must never affect canonical set or dictionary order.
  for i in 0..<32:
    # The first unequal octet decides order; identical hashes fall through to false.
    if a.bytes[i] != b.bytes[i]: return a.bytes[i] < b.bytes[i]
  false

proc decodeReportBorrowed*(input: openArray[byte], coreCount: uint64): ReportResult {.raises: [].} =
  ## Decode one bounded complete report prefix without allocation; spans use original whole-input coordinates.
  let header = decodeReportHeader(input)
  # A missing fixed header cannot construct a report with invented default fields.
  if header.error != CompositeError.None: return ReportResult(status: header.error)
  # A chain profile cannot have more assurers than three times its configured core ceiling.
  if uint64(header.value.erasureShards) div 3 > coreCount:
    return ReportResult(status: CompositeError.LimitExceeded)
  var value = WorkReport(header: header.value)
  var cursor = 272
  # Read a canonical natural into private parser state, never into a caller-visible partial report.
  template readNumber(target: untyped) =
    block:
      let parsed = natural.decode(input.toOpenArray(cursor, input.high))
      # Preserve precise natural failure before advancing or narrowing an attacker-supplied count.
      if not parsed.ok:
        return ReportResult(status: if parsed.error ==
            natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
      target = uint64(parsed.value)
      cursor += parsed.consumed
  var count: uint64 = 0
  readNumber(count)
  # Protocol count policy precedes the fixed-stride extent proof and narrowing to a host index.
  if count > 8: return ReportResult(status: CompositeError.LimitExceeded)
  if count > uint64((input.len-cursor) div 32): return ReportResult(
      status: CompositeError.Truncated)
  value.prerequisiteCount = int(count)
  # Prerequisites form an ordered unique set; received metadata is never silently sorted.
  for i in 0..<value.prerequisiteCount:
    # The complete fixed-stride extent was checked before entering this loop.
    for j in 0..<32: value.prerequisites[i].bytes[j] = input[cursor+j]
    cursor += 32
    # Duplicate and descending set members are equally noncanonical.
    if i > 0 and not reportHashLess(value.prerequisites[i-1], value.prerequisites[i]):
      return ReportResult(status: CompositeError.NonCanonical)
  readNumber(count)
  value.core = CoreIndex(count)
  # Core bounds come from explicit chain configuration, not inferred from available input bytes.
  if count >= coreCount: return ReportResult(status: CompositeError.LimitExceeded)
  if input.len-cursor < 32: return ReportResult(status: CompositeError.Truncated)
  # Authorizer identity is an owned copy rather than an input-buffer view.
  for i in 0..<32: value.authorizer.bytes[i] = input[cursor+i]
  cursor += 32
  readNumber(count)
  value.authGas = Gas(count)
  let auth = decodeBytesBorrowed(input.toOpenArray(cursor, input.high), ByteLimit(49152))
  # Authorization payload length/policy/extent must validate before binding its descriptor.
  if auth.error != ContainerError.None:
    return ReportResult(status: if auth.error == ContainerError.Truncated: CompositeError.Truncated elif auth.error ==
        ContainerError.NonCanonical: CompositeError.NonCanonical else: CompositeError.LimitExceeded)
  value.authOutput = BlobSpan(offset: cursor+auth.offset, length: auth.length)
  cursor += auth.consumed
  var total = value.authOutput.length
  readNumber(count)
  # Lookup keys and prerequisites share one eight-entry dependency budget.
  if count > uint64(8-value.prerequisiteCount): return ReportResult(
      status: CompositeError.LimitExceeded)
  if count > uint64((input.len-cursor) div 64): return ReportResult(
      status: CompositeError.Truncated)
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
      return ReportResult(status: CompositeError.NonCanonical)
  readNumber(count)
  # Counts cannot index fixed digest capacity before this protocol-bound proof.
  if count < 1 or count > 16: return ReportResult(status: CompositeError.LimitExceeded)
  value.digestCount = int(count)
  # Every child, including its final metric, must validate before any successful report is returned.
  for i in 0..<value.digestCount:
    let parsed = decodeDigestBorrowed(input.toOpenArray(cursor, input.high), ByteLimit(49152-total))
    # Preserve exact nested failures, including the remaining aggregate blob budget.
    if parsed.error != CompositeError.None: return ReportResult(status: parsed.error)
    var digest = parsed.value
    # Successful payloads alone consume aggregate budget and need whole-input coordinates.
    if digest.output.kind == WorkKind.Success:
      let span = digest.output.blob
      total += span.length
      # Rebuild the copied work variant so spans address the original complete-report input.
      digest.output = successfulWork(BlobSpan(offset: span.offset + cursor, length: span.length))
    value.digests[i] = digest
    cursor += parsed.consumed
  ReportResult(status: CompositeError.None, decodedValue: value, byteConsumed: cursor)

proc measureReportBorrowed*(value: WorkReport, poolSize: int,
    coreCount: uint64): CompositeWrite {.raises: [].} =
  # Header-domain checks precede all size measurement and preserve encoder atomicity.
  if not validErasureShards(value.header.erasureShards) or
      uint64(value.header.erasureShards) div 3 > coreCount:
    return compositeFailure(CompositeError.LimitExceeded)
  # Signed public counts must fit bounded metadata before any array indexing or multiplication.
  if value.prerequisiteCount < 0 or value.prerequisiteCount > 8 or value.lookupCount < 0 or
      value.lookupCount > 8 or value.lookupCount > 8-value.prerequisiteCount or value.digestCount <
      1 or value.digestCount > 16 or uint64(value.core) >= coreCount:
    return compositeFailure(CompositeError.LimitExceeded)
  let span = value.authOutput
  # Subtraction proves endpoint arithmetic, including an empty span at the pool end.
  if span.offset < 0 or span.length < 0 or span.offset > poolSize or span.length >
      poolSize-span.offset:
    return compositeFailure(CompositeError.InvalidSpan)
  var total = span.length
  if total > 49152: return compositeFailure(CompositeError.LimitExceeded)
  # Encoders require canonical ordered input instead of silently sorting caller metadata.
  for i in 1..<value.prerequisiteCount:
    if not reportHashLess(value.prerequisites[i-1], value.prerequisites[i]):
      return compositeFailure(CompositeError.NonCanonical)
  # Only dictionary package keys decide ordering and uniqueness.
  for i in 1..<value.lookupCount:
    if not reportHashLess(value.lookup[i-1].packageHash, value.lookup[i].packageHash):
      return compositeFailure(CompositeError.NonCanonical)
  var required = 272 + natural.encode(JamNatural(value.prerequisiteCount)).len +
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
    if size > high(int)-required: return compositeFailure(CompositeError.LengthOverflow)
    required += size
  compositeWritten(required)

# Commit one canonical natural into a proven complete destination extent; no allocations are required.
proc reportPutNatural(number: uint64, output: var openArray[byte], cursor: var int) {.raises: [].} =
  let encoded = natural.encode(JamNatural(number))
  # All target bytes belong to the enclosing encoder's preflighted extent.
  for i in 0..<encoded.len: output[cursor+i] = encoded.bytes[i]
  cursor += encoded.len

proc encodeReportBorrowed*(source: WorkReport, pool: openArray[byte], coreCount: uint64,
    output: var openArray[byte]): CompositeWrite {.raises: [].} =
  ## Encode a value snapshot atomically, preserving the entire borrowed pool against overlap.
  let value = source
  let measured = measureReportBorrowed(value, pool.len, coreCount)
  # No mutation is permitted until all fixed fields and the final nested metric have validated.
  if measured.error != CompositeError.None: return measured
  let required = measured.written
  if output.len < required: return compositeFailure(CompositeError.OutputTooSmall)
  # Compare address differences without overflowing pointer-end arithmetic; empty pools do not alias.
  if pool.len > 0:
    let a = cast[uint](unsafeAddr pool[0])
    let b = cast[uint](addr output[0])
    if (a <= b and b-a < uint(pool.len)) or (b < a and a-b < uint(required)):
      return compositeFailure(CompositeError.AliasedBuffers)
  discard encodeReportHeader(value.header, output.toOpenArray(0, 271))
  var cursor = 272
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
    assert encoded.error == CompositeError.None
    cursor += encoded.written
  compositeWritten(cursor)
