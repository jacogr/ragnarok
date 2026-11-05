# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact per-shard persistence records check chain identity, complete metadata and CE137 proofs; record success alone is neither durable publication nor assurance authority.
import std/assertions
import ./availability_proof
import ../state/availability/specifier
import ../state/erasure/words
import ../codec/bounded
import ../codec/work/report
import ../crypto/primitives

const
  AssuranceRetentionSeconds* = 28'u64*24*60*60 ## GP assurance.tex's duration is independent of validator epoch and slot geometry.
  AssuranceRecordHeaderBytes* = 206 ## Fixed 174-byte versioned metadata and its Blake2b-256 checksum precede exactly three payloads.
  MaxAssuranceRecordBytes* = 16'u64*1024*1024+uint64(
      AssuranceRecordHeaderBytes) ## CE137's independent aggregate ceiling bounds one record's native allocations.
  RecordMagic = "RAGAS001"
type
  AssuranceChainId* = distinct array[32, byte] ## Expected configured chain identity is separate from shard roots and the current assurance anchor.
  AssuranceTime* = distinct uint64 ## Whole seconds since the GP Common Era, never a timeslot or an epoch count.
  AssuranceRecordLimits* = object ## Serialized size and complete metadata-plus-proof verification have independent explicit resource bounds.
    bytes*: ByteLimit
    verification*: AvailabilityMerkleLimits
  AssuranceRecordInfo* = object ## Copied fixed metadata grants no durability, signing, current duty or canonical inclusion authority.
    chain*: AssuranceChainId
    specifier*: AvailabilitySpecifier
    shard*: ErasureShardIndex
    promisedAt*, retainUntil*: AssuranceTime
    bundleBytes*, segmentBytes*, proofBytes*, encodedBytes*: uint64
  RecordData = ref object ## Source-free immutable verified bytes can retire independently of an incoming transfer or execution session.
    info: AssuranceRecordInfo
    transfer: VerifiedAvailabilityTransfer
  AssuranceRecord* = object ## Only a full verified transfer or complete record verification constructs this private owner.
    data: nil RecordData
  AssuranceRecordError* {.pure.} = enum ## Failure/default alternatives contain no accepted record, metadata prefix or possession receipt.
    Uninitialized, None, InvalidSource, InvalidFormat, WrongChain, InvalidTime,
    LimitExceeded, ChecksumMismatch, PlanFailure, TransferFailure, BackendFailure
  AssuranceRecordResult*[T] = object ## Selected genuine planning, transfer and primitive failures remain distinguishable.
    case status: AssuranceRecordError
    of None: completed: T
    of PlanFailure: planReason: AvailabilityTransferResult[AvailabilityVerificationInfo]
    of TransferFailure: transferReason: AvailabilityTransferResult[VerifiedAvailabilityTransfer]
    of BackendFailure: cryptoReason: CryptoError
    else: discard # A failed value never exposes bytes or a successful default record.
func error*[T](outcome: AssuranceRecordResult[T]): AssuranceRecordError =
  ## Inspect the immutable status before selecting metadata, an owner or a child failure.
  outcome.status
func value*[T](outcome: AssuranceRecordResult[T]): T {.requires: outcome.status ==
    AssuranceRecordError.None.} =
  ## A refused or default operation exposes no successful prefix.
  outcome.completed
func planError*[T](outcome: AssuranceRecordResult[T]): AvailabilityTransferResult[
    AvailabilityVerificationInfo] {.requires: outcome.status == AssuranceRecordError.PlanFailure.} =
  ## Preserve the exact failed expected-geometry calculation, including selected child causes.
  outcome.planReason
func transferError*[T](outcome: AssuranceRecordResult[T]): AvailabilityTransferResult[
    VerifiedAvailabilityTransfer] {.requires: outcome.status ==
    AssuranceRecordError.TransferFailure.} =
  ## Preserve the actual failed verification or private-detach operation.
  outcome.transferReason
func cryptoError*[T](outcome: AssuranceRecordResult[T]): CryptoError {.requires: outcome.status ==
    AssuranceRecordError.BackendFailure.} =
  ## Preserve only the actual failed metadata checksum primitive.
  outcome.cryptoReason
func refused[T](reason: AssuranceRecordError): AssuranceRecordResult[T] {.requires: reason notin {
    AssuranceRecordError.None, AssuranceRecordError.PlanFailure,
    AssuranceRecordError.TransferFailure, AssuranceRecordError.BackendFailure}.} =
  ## Simple refusals carry no unrelated child diagnostic or accepted prefix.
  AssuranceRecordResult[T](status: reason)
func propagated[T, U](outcome: AssuranceRecordResult[U]): AssuranceRecordResult[
    T] {.requires: outcome.status != AssuranceRecordError.None.} =
  ## Translate only a genuine selected refusal; no successful child prefix is retained.
  case outcome.status
  of AssuranceRecordError.PlanFailure: AssuranceRecordResult[T](
      status: AssuranceRecordError.PlanFailure, planReason: outcome.planReason)
  of AssuranceRecordError.TransferFailure: AssuranceRecordResult[T](
      status: AssuranceRecordError.TransferFailure, transferReason: outcome.transferReason)
  of AssuranceRecordError.BackendFailure: AssuranceRecordResult[T](
      status: AssuranceRecordError.BackendFailure, cryptoReason: outcome.cryptoReason)
  of AssuranceRecordError.None: refused[T](AssuranceRecordError.Uninitialized) # The precondition excludes this unreachable branch.
  else: refused[T](outcome.status)
func valid*(record: AssuranceRecord): bool =
  ## A default handle has no verified payload and cannot become a persistence candidate.
  record.data != nil
proc recordInfo*(record: AssuranceRecord): AssuranceRecordResult[AssuranceRecordInfo] =
  ## Only fixed copied fields leave the immutable owner.
  let data = record.data
  if data == nil: return refused[AssuranceRecordInfo](AssuranceRecordError.Uninitialized)
  AssuranceRecordResult[AssuranceRecordInfo](status: AssuranceRecordError.None,
      completed: data.info)
func valid*(limits: AssuranceRecordLimits): bool =
  ## Native extents remain below seventeen MiB; no default policy permits an allocation or checksum.
  uint64(limits.bytes) >= uint64(AssuranceRecordHeaderBytes) and uint64(limits.bytes) <=
      MaxAssuranceRecordBytes and uint64(limits.verification.bytes) > 0 and uint64(
      limits.verification.hashes) > 0 and uint64(limits.verification.hashBytes) > 0
func sameSpecifier*(left, right: AvailabilitySpecifier): bool =
  ## Exact persisted context includes all six fields; root equality alone cannot replace canonical metadata.
  left.packageHash.bytes == right.packageHash.bytes and uint32(left.bundleLength) == uint32(
      right.bundleLength) and left.erasureRoot.bytes == right.erasureRoot.bytes and uint16(
      left.erasureShards) == uint16(right.erasureShards) and left.segmentRoot.bytes ==
      right.segmentRoot.bytes and uint16(left.segmentCount) == uint16(right.segmentCount)
func number(wire: openArray[byte], start, width: int): uint64 {.requires: start >= 0 and width >=
    1 and width <= 8 and start <= wire.len and width <= wire.len-start.} =
  ## Fixed little-endian metadata widths are checked by whole-header admission before access.
  result = 0
  for index in 0..<width:
    # At most eight octets make every shift fit the unsigned 64-bit accumulator.
    result = result or (uint64(wire[start+index]) shl (index*8))
proc putNumber(wire: var seq[byte], start, width: int, value: uint64) =
  ## Encoder callers allocate the entire bounded record before writing fixed metadata extents.
  assert start >= 0 and width >= 1 and width <= 8 and start <= wire.len and width <= wire.len-start
  for index in 0..<width:
    # All serialized numeric domains have already been proved to fit their declared widths.
    wire[start+index] = byte((value shr (index*8)) and 255)
func admitted(info: AssuranceRecordInfo, work: AvailabilityVerificationInfo,
    limits: AssuranceRecordLimits, verify: bool): bool =
  ## Charge worst-case owned extraction/input/output buffers and the exact complete checksum/proof work before allocation or hashing.
  if not limits.valid or info.encodedBytes > uint64(limits.bytes): return false
  let workspace = work.payloadBytes*3+uint64(AssuranceRecordHeaderBytes)
  if workspace > uint64(limits.verification.bytes): return false
  if uint64(limits.verification.hashes) < 1 or uint64(limits.verification.hashBytes) <
      174: return false
  if verify:
    # Subtraction avoids wrapping when a caller provides a smaller aggregate budget than the metadata hash alone.
    if work.hashes > uint64(limits.verification.hashes)-1 or work.hashBytes > uint64(
        limits.verification.hashBytes)-174: return false
  true
proc plannedInfo(info: AssuranceRecordInfo): AvailabilityTransferResult[
    AvailabilityVerificationInfo] =
  ## Record inputs cannot select another transfer kind or row namespace.
  availabilityVerificationInfo(info.specifier, AvailabilityRequest(
    kind: AvailabilityTransferKind.Distribution,
    root: info.specifier.erasureRoot, shard: info.shard))
proc prepareAssuranceRecord*(source: VerifiedAvailabilityTransfer, chain: AssuranceChainId,
    now: AssuranceTime, limits: AssuranceRecordLimits): AssuranceRecordResult[AssuranceRecord] =
  ## A fresh private copy records a full 28-day obligation without claiming any I/O or signing authority.
  if not source.valid: return refused[AssuranceRecord](AssuranceRecordError.InvalidSource)
  if source.request.kind != AvailabilityTransferKind.Distribution: return refused[AssuranceRecord](
      AssuranceRecordError.InvalidSource)
  let clock = uint64(now)
  if clock > high(uint64)-AssuranceRetentionSeconds: return refused[AssuranceRecord](
      AssuranceRecordError.InvalidTime)
  var info = AssuranceRecordInfo(chain: chain, specifier: source.specifier,
    shard: source.request.shard,
    promisedAt: now, retainUntil: AssuranceTime(clock+AssuranceRetentionSeconds))
  let plan = plannedInfo(info)
  if plan.error != AvailabilityTransferError.None: return AssuranceRecordResult[AssuranceRecord](
      status: AssuranceRecordError.PlanFailure, planReason: plan)
  let work = plan.value
  info.bundleBytes = work.bundleBytes
  info.segmentBytes = work.segmentBytes
  info.proofBytes = work.proofBytes
  info.encodedBytes = uint64(AssuranceRecordHeaderBytes)+work.payloadBytes
  if not admitted(info, work, limits, false): return refused[AssuranceRecord](
      AssuranceRecordError.LimitExceeded)
  let detached = detachVerifiedAvailability(source, ByteLimit(work.payloadBytes))
  if detached.error != AvailabilityTransferError.None: return AssuranceRecordResult[
      AssuranceRecord](status: AssuranceRecordError.TransferFailure, transferReason: detached)
  AssuranceRecordResult[AssuranceRecord](status: AssuranceRecordError.None,
    completed: AssuranceRecord(data: RecordData(info: info, transfer: detached.value)))
proc renewAssuranceRecord*(record: AssuranceRecord, now: AssuranceTime,
    limits: AssuranceRecordLimits): AssuranceRecordResult[AssuranceRecord] =
  ## Renewal preserves every existing promise and immutable payload; all shared aliases must retire before any later worker handoff.
  let data = record.data
  if data == nil: return refused[AssuranceRecord](AssuranceRecordError.Uninitialized)
  let clock = uint64(now)
  if clock < uint64(data.info.promisedAt) or clock > high(uint64)-AssuranceRetentionSeconds:
    return refused[AssuranceRecord](AssuranceRecordError.InvalidTime)
  let plan = plannedInfo(data.info)
  if plan.error != AvailabilityTransferError.None: return AssuranceRecordResult[AssuranceRecord](
      status: AssuranceRecordError.PlanFailure, planReason: plan)
  if not admitted(data.info, plan.value, limits, false): return refused[AssuranceRecord](
      AssuranceRecordError.LimitExceeded)
  var info = data.info
  info.promisedAt = now
  info.retainUntil = AssuranceTime(max(uint64(info.retainUntil), clock+AssuranceRetentionSeconds))
  AssuranceRecordResult[AssuranceRecord](status: AssuranceRecordError.None,
    completed: AssuranceRecord(data: RecordData(info: info, transfer: data.transfer)))
proc recordMatches*(record: AssuranceRecord, expected: AvailabilitySpecifier,
    request: AvailabilityRequest): bool =
  ## A self-rooted persisted proof cannot replace independently canonical package/geometry metadata or the exact assigned coordinate.
  let data = record.data
  if data == nil or request.kind != AvailabilityTransferKind.Distribution or uint64(request.row) !=
      0: return false
  request.root.bytes == expected.erasureRoot.bytes and uint64(request.shard) == uint64(
      data.info.shard) and sameSpecifier(data.info.specifier, expected)
proc encodeAssuranceRecord*(record: AssuranceRecord,
    limits: AssuranceRecordLimits): AssuranceRecordResult[seq[byte]] =
  ## Encode exact metadata and authenticated payloads only after complete size/work preflight; no partially encoded record escapes.
  let data = record.data
  if data == nil: return refused[seq[byte]](AssuranceRecordError.Uninitialized)
  let info = data.info
  let plan = plannedInfo(info)
  if plan.error != AvailabilityTransferError.None: return AssuranceRecordResult[seq[byte]](
      status: AssuranceRecordError.PlanFailure, planReason: plan)
  if not admitted(info, plan.value, limits, false): return refused[seq[byte]](
      AssuranceRecordError.LimitExceeded)
  var wire = newSeq[byte](int(info.encodedBytes))
  for index in 0..<8: wire[index] = byte(RecordMagic[index])
  for index in 0..<32:
    # Every fixed identity remains exact and domain-separated by its declared field and file version.
    wire[8+index] = array[32, byte](info.chain)[index]
    wire[40+index] = info.specifier.packageHash.bytes[index]
    wire[76+index] = info.specifier.erasureRoot.bytes[index]
    wire[110+index] = info.specifier.segmentRoot.bytes[index]
  putNumber(wire, 72, 4, uint64(uint32(info.specifier.bundleLength)))
  putNumber(wire, 108, 2, uint64(uint16(info.specifier.erasureShards)))
  putNumber(wire, 142, 2, uint64(uint16(info.specifier.segmentCount)))
  putNumber(wire, 144, 2, uint64(info.shard))
  putNumber(wire, 146, 8, uint64(info.promisedAt))
  putNumber(wire, 154, 8, uint64(info.retainUntil))
  putNumber(wire, 162, 4, info.bundleBytes)
  putNumber(wire, 166, 4, info.segmentBytes)
  putNumber(wire, 170, 4, info.proofBytes)
  let checksum = blake2b256(wire.toOpenArray(0, 173))
  if checksum.error != CryptoError.None: return AssuranceRecordResult[seq[byte]](
      status: AssuranceRecordError.BackendFailure, cryptoReason: checksum.error)
  for index in 0..<32: wire[174+index] = array[32, byte](checksum.value)[index]
  var position = AssuranceRecordHeaderBytes
  for part in [data.transfer.bundleShard, data.transfer.segmentShards, data.transfer.justification]:
    # Extracted copies are immutable input; exact precharged lengths prove every final output index.
    for octet in part:
      wire[position] = octet
      inc position
  assert position == wire.len
  AssuranceRecordResult[seq[byte]](status: AssuranceRecordError.None, completed: wire)
proc parseHeader(header: openArray[byte], chain: AssuranceChainId,
    limits: AssuranceRecordLimits): AssuranceRecordResult[AssuranceRecordInfo] =
  ## Parse and preflight every fixed extent without invoking a checksum or payload primitive.
  if header.len != AssuranceRecordHeaderBytes: return refused[AssuranceRecordInfo](
      AssuranceRecordError.InvalidFormat)
  for index in 0..<8:
    # A different physical schema never becomes a fallback decoder.
    if header[index] != byte(RecordMagic[index]): return refused[AssuranceRecordInfo](
        AssuranceRecordError.InvalidFormat)
  var info = default(AssuranceRecordInfo)
  var savedChain = default(array[32, byte])
  for index in 0..<32:
    # Only fixed bounded values are copied before the complete metadata shape is checked.
    savedChain[index] = header[8+index]
    info.specifier.packageHash.bytes[index] = header[40+index]
    info.specifier.erasureRoot.bytes[index] = header[76+index]
    info.specifier.segmentRoot.bytes[index] = header[110+index]
  if savedChain != array[32, byte](chain): return refused[AssuranceRecordInfo](
      AssuranceRecordError.WrongChain)
  info.chain = chain
  info.specifier.bundleLength = BundleLength(uint32(number(header, 72, 4)))
  info.specifier.erasureShards = ErasureShards(uint16(number(header, 108, 2)))
  info.specifier.segmentCount = SegmentCount(uint16(number(header, 142, 2)))
  info.shard = ErasureShardIndex(number(header, 144, 2))
  info.promisedAt = AssuranceTime(number(header, 146, 8))
  info.retainUntil = AssuranceTime(number(header, 154, 8))
  if uint64(info.promisedAt) > high(uint64)-AssuranceRetentionSeconds: return refused[
      AssuranceRecordInfo](AssuranceRecordError.InvalidTime)
  if uint64(info.retainUntil) < uint64(info.promisedAt)+AssuranceRetentionSeconds: return refused[
      AssuranceRecordInfo](AssuranceRecordError.InvalidTime)
  info.bundleBytes = number(header, 162, 4)
  info.segmentBytes = number(header, 166, 4)
  info.proofBytes = number(header, 170, 4)
  let plan = plannedInfo(info)
  if plan.error != AvailabilityTransferError.None: return AssuranceRecordResult[
      AssuranceRecordInfo](status: AssuranceRecordError.PlanFailure, planReason: plan)
  let work = plan.value
  if info.bundleBytes != work.bundleBytes or info.segmentBytes != work.segmentBytes or
      info.proofBytes != work.proofBytes: return refused[AssuranceRecordInfo](
      AssuranceRecordError.InvalidFormat)
  info.encodedBytes = uint64(AssuranceRecordHeaderBytes)+work.payloadBytes
  if not admitted(info, work, limits, false): return refused[AssuranceRecordInfo](
      AssuranceRecordError.LimitExceeded)
  AssuranceRecordResult[AssuranceRecordInfo](status: AssuranceRecordError.None, completed: info)
proc verifyMetadata(header: openArray[byte]): AssuranceRecordResult[bool] =
  ## Callers have already charged whole-operation work and admitted the fixed header before this first hash.
  assert header.len >= AssuranceRecordHeaderBytes
  let checksum = blake2b256(header.toOpenArray(0, 173))
  if checksum.error != CryptoError.None: return AssuranceRecordResult[bool](
      status: AssuranceRecordError.BackendFailure, cryptoReason: checksum.error)
  for index in 0..<32:
    # Integrity covers chain identity, all six availability fields, every extent and the complete retention obligation.
    if array[32, byte](checksum.value)[index] != header[174+index]: return refused[bool](
        AssuranceRecordError.ChecksumMismatch)
  AssuranceRecordResult[bool](status: AssuranceRecordError.None, completed: true)
proc inspectAssuranceRecord*(header: openArray[byte], chain: AssuranceChainId,
    limits: AssuranceRecordLimits): AssuranceRecordResult[AssuranceRecordInfo] =
  ## Bounded directory scans verify metadata without reading shard payloads; copied metadata is not possession evidence.
  let parsed = parseHeader(header, chain, limits)
  if parsed.error != AssuranceRecordError.None: return parsed
  let checksum = verifyMetadata(header)
  if checksum.error != AssuranceRecordError.None: return propagated[AssuranceRecordInfo, bool](checksum)
  parsed
proc verifyPayload(wire: openArray[byte], info: AssuranceRecordInfo,
    limits: AvailabilityMerkleLimits): AvailabilityTransferResult[VerifiedAvailabilityTransfer] =
  ## Metadata shape and full file size have proved these bounded integer conversions and exact component ranges.
  let bundleEnd = AssuranceRecordHeaderBytes+int(info.bundleBytes)
  let segmentEnd = bundleEnd+int(info.segmentBytes)
  let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
    root: info.specifier.erasureRoot, shard: info.shard)
  if info.segmentBytes == 0:
    # Zero exports have no segment payload; use an actual empty view rather than constructing an invalid inclusive slice.
    return verifyAvailabilityTransfer(info.specifier, request,
      wire.toOpenArray(AssuranceRecordHeaderBytes, bundleEnd-1), [],
      wire.toOpenArray(segmentEnd, wire.len-1), limits)
  verifyAvailabilityTransfer(info.specifier, request,
    wire.toOpenArray(AssuranceRecordHeaderBytes, bundleEnd-1),
    wire.toOpenArray(bundleEnd, segmentEnd-1), wire.toOpenArray(segmentEnd, wire.len-1), limits)
proc decodeAssuranceRecord*(wire: openArray[byte], chain: AssuranceChainId,
    limits: AssuranceRecordLimits): AssuranceRecordResult[AssuranceRecord] =
  ## Complete exact EOF, fixed metadata, aggregate work and all CE137 proof checks precede a restored record owner.
  if not limits.valid or uint64(wire.len) > uint64(limits.bytes): return refused[AssuranceRecord](
      AssuranceRecordError.LimitExceeded)
  if wire.len < AssuranceRecordHeaderBytes: return refused[AssuranceRecord](
      AssuranceRecordError.InvalidFormat)
  let inspected = parseHeader(wire.toOpenArray(0, AssuranceRecordHeaderBytes-1), chain, limits)
  if inspected.error != AssuranceRecordError.None: return propagated[AssuranceRecord,
      AssuranceRecordInfo](inspected)
  let info = inspected.value
  if uint64(wire.len) != info.encodedBytes: return refused[AssuranceRecord](
      AssuranceRecordError.InvalidFormat)
  let plan = plannedInfo(info)
  assert plan.error == AvailabilityTransferError.None
  if not admitted(info, plan.value, limits, true): return refused[AssuranceRecord](
      AssuranceRecordError.LimitExceeded)
  let checksum = verifyMetadata(wire)
  if checksum.error != AssuranceRecordError.None: return propagated[AssuranceRecord, bool](checksum)
  let verified = verifyPayload(wire, info, limits.verification)
  if verified.error != AvailabilityTransferError.None: return AssuranceRecordResult[
      AssuranceRecord](status: AssuranceRecordError.TransferFailure, transferReason: verified)
  AssuranceRecordResult[AssuranceRecord](status: AssuranceRecordError.None,
    completed: AssuranceRecord(data: RecordData(info: info, transfer: verified.value)))
proc recordTransfer*(record: AssuranceRecord, maximum: ByteLimit): AvailabilityTransferResult[
    VerifiedAvailabilityTransfer] =
  ## Return a detached verified copy for later serving without exposing the persistence owner's ARC graph to another worker lifetime.
  let data = record.data
  if data == nil: return detachVerifiedAvailability(default(VerifiedAvailabilityTransfer), maximum)
  detachVerifiedAvailability(data.transfer, maximum)
