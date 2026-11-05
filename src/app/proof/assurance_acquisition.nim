# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed canonical CE137 acquisition verifies exact three-message framing and all assigned shard data before synchronized retention; fixed completion facts grant no signing capability.
import std/assertions
import ../../jamnp-s/[assurance_duty, assurance_store, assurance_record, availability_proof]
import ../../chain/genesis
import ../../codec/[bounded, assurances, report_owned, owned]
import ../../codec/state/[safrole, availability]
import ../../codec/work/report
import ../../state/availability/specifier

type
  AssuranceAcquisitionLimits* = object ## Canonical chapter reads, incoming proof work, raw wire and aggregate transfer-buffer workspace have independent explicit ceilings.
    duty*: AssuranceDutyLimits
    verification*: AvailabilityMerkleLimits
    wireBytes*, workspaceBytes*: ByteLimit
  AssuranceAcquisitionInfo* = object ## Detached fixed progress facts certify neither current canonical duty nor possession/signing authority after this job retires.
    duty*: AssuranceDutyInfo
    core*: CoreIndex
    validator*: ValidatorIndex
    record*: AssuranceRecordInfo
  AcquisitionData = ref object ## One acyclic immutable input owns raw bytes and the selected complete source while borrowing a stable namespace through collection/join.
    owner: ptr AssuranceStore
    source: BlockSnapshotResult
    chain: AssuranceChainId
    local: StateEdKey
    core: CoreIndex
    ordinal: int
    wire: seq[byte]
    now: AssuranceTime
    limits: AssuranceAcquisitionLimits
  AssuranceAcquisitionJob* = object ## Only bounded capture can stage this closed source/verification/retention operation.
    data: nil AcquisitionData
  AssuranceAcquisitionError* {.pure.} = enum ## Default/refused operations carry no partial data, possession bit or signing capability.
    Uninitialized, None, Closed, Faulted, WrongChain, InvalidSource, InvalidInput, InvalidPolicy,
      LimitExceeded, Cancelled, DutyFailure, TransferFailure, StorageFailure
  AssuranceAcquisitionResult*[T] = object ## Each actual failed child remains selected without exposing a successful source or shard prefix.
    case status: AssuranceAcquisitionError
    of None: completed: T
    of DutyFailure: dutyReason: AssuranceDutyResult[AssuranceDuty]
    of TransferFailure: transferReason: AvailabilityTransferResult[VerifiedAvailabilityTransfer]
    of StorageFailure: storageReason: AssuranceStoreResult[StoredAssuranceShard]
    else: discard # Simple/default refusals retain no successful input, receipt or unrelated child reason.
  FrameParts = object ## Borrowed extents stay inside the synchronous native operation and never escape their raw input owner.
    starts, lengths: array[3, int]
func error*[T](outcome: AssuranceAcquisitionResult[T]): AssuranceAcquisitionError =
  ## Inspect the selected failure before extracting its guarded payload or child.
  outcome.status
func value*[T](outcome: AssuranceAcquisitionResult[T]): T {.requires: outcome.status ==
    AssuranceAcquisitionError.None.} =
  ## Only completely admitted jobs or completely persisted progress facts are extractable.
  outcome.completed
func dutyError*[T](outcome: AssuranceAcquisitionResult[T]): AssuranceDutyResult[
    AssuranceDuty] {.requires: outcome.status == AssuranceAcquisitionError.DutyFailure.} =
  ## Preserve the actual selected canonical-source qualification failure.
  outcome.dutyReason
func transferError*[T](outcome: AssuranceAcquisitionResult[T]): AvailabilityTransferResult[
    VerifiedAvailabilityTransfer] {.requires: outcome.status ==
    AssuranceAcquisitionError.TransferFailure.} =
  ## Preserve real expected-geometry, proof or maintained-primitive failure.
  outcome.transferReason
func storageError*[T](outcome: AssuranceAcquisitionResult[T]): AssuranceStoreResult[
    StoredAssuranceShard] {.requires: outcome.status == AssuranceAcquisitionError.StorageFailure.} =
  ## A failed durability boundary cannot be replaced with successful acquisition metadata.
  outcome.storageReason
func refused[T](reason: AssuranceAcquisitionError): AssuranceAcquisitionResult[
    T] {.requires: reason notin {AssuranceAcquisitionError.None,
    AssuranceAcquisitionError.DutyFailure, AssuranceAcquisitionError.TransferFailure,
    AssuranceAcquisitionError.StorageFailure}.} =
  ## Simple refusal owns no partially initialized child or accepted payload.
  AssuranceAcquisitionResult[T](status: reason)
func valid*(limits: AssuranceAcquisitionLimits): bool =
  ## Existing public CE137 framing stays within 16MiB; checked logical buffer accounting remains bounded independently of archive size.
  uint64(limits.duty.chapterBytes) > 0 and uint64(limits.duty.readBytes) > 0 and
    uint64(limits.duty.reports) > 0 and uint64(limits.duty.requests) > 0 and
    uint64(limits.wireBytes) >= 12 and uint64(limits.wireBytes) <= 16'u64*1024*1024 and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 256'u64*1024*1024 and
    uint64(limits.verification.bytes) > 0 and uint64(limits.verification.bytes) <=
        256'u64*1024*1024 and
    uint64(limits.verification.hashes) > 0 and uint64(limits.verification.hashes) <= 1000000 and
    uint64(limits.verification.hashBytes) > 0 and uint64(limits.verification.hashBytes) <=
        128'u64*1024*1024
func valid*(job: AssuranceAcquisitionJob): bool =
  ## Default jobs retain no source, path, native owner or input bytes.
  job.data != nil
proc captureAssuranceAcquisition*(owner: var AssuranceStore, source: BlockSnapshotResult,
    chain: AssuranceChainId, local: StateEdKey, core: CoreIndex, ordinal: int,
    wire: openArray[byte], now: AssuranceTime, limits: AssuranceAcquisitionLimits): AssuranceAcquisitionResult[
        AssuranceAcquisitionJob] =
  ## Capture performs no proof work or filesystem I/O; every source/raw-frame alias and the fixed owner stay frozen until exact collection/join.
  if not owner.opened: return refused[AssuranceAcquisitionJob](AssuranceAcquisitionError.Closed)
  if owner.faulted: return refused[AssuranceAcquisitionJob](AssuranceAcquisitionError.Faulted)
  if not owner.matchesChain(chain): return refused[AssuranceAcquisitionJob](
      AssuranceAcquisitionError.WrongChain)
  if source.error != GenesisError.None: return refused[AssuranceAcquisitionJob](
      AssuranceAcquisitionError.InvalidSource)
  if not limits.valid: return refused[AssuranceAcquisitionJob](
      AssuranceAcquisitionError.InvalidPolicy)
  if ordinal < 0 or ordinal >= 1023 or uint64(core) >= 341 or wire.len < 12:
    return refused[AssuranceAcquisitionJob](AssuranceAcquisitionError.InvalidInput)
  if uint64(wire.len) > uint64(limits.wireBytes) or uint64(wire.len) > uint64(
      limits.workspaceBytes):
    return refused[AssuranceAcquisitionJob](AssuranceAcquisitionError.LimitExceeded)
  var copied = newSeq[byte](wire.len)
  for index in 0..<wire.len: copied[index] = wire[
      index] # Raw callback/input owners may retire before execution, independently of the canonical snapshot lease.
  AssuranceAcquisitionResult[AssuranceAcquisitionJob](status: AssuranceAcquisitionError.None,
    completed: AssuranceAcquisitionJob(data: AcquisitionData(owner: addr owner, source: source,
      chain: chain, local: local, core: core, ordinal: ordinal, wire: copied, now: now,
      limits: limits)))
func frames(wire: openArray[byte], lengths: array[3, uint64], parts: var FrameParts): bool =
  ## Exact E4 extents come from the canonical report geometry, never peer-selected counts; reject every truncated prefix, body or suffix before hashing.
  parts = default(FrameParts)
  var offset = 0
  for index in 0..<3:
    # Subtraction proves prefix/body arithmetic and every conversion into the bounded input's native index domain.
    if offset > wire.len or wire.len-offset < 4: return false
    var count = 0'u64
    for octet in 0..<4: count = count or (uint64(wire[offset+octet]) shl (8*octet))
    offset += 4
    if count != lengths[index] or count > uint64(wire.len-offset): return false
    parts.starts[index] = offset
    parts.lengths[index] = int(count)
    offset += int(count)
  offset == wire.len
proc verify(data: AcquisitionData, expected: AvailabilitySpecifier, request: AvailabilityRequest,
    parts: FrameParts): AvailabilityTransferResult[VerifiedAvailabilityTransfer] =
  ## Empty export or singleton-proof extents use genuine empty views, never invalid negative array slices.
  let bundle = parts.starts[0]
  let segments = parts.starts[1]
  let proof = parts.starts[2]
  if parts.lengths[1] == 0:
    if parts.lengths[2] == 0:
      return verifyAvailabilityTransfer(expected, request,
        data.wire.toOpenArray(bundle, bundle+parts.lengths[0]-1), [], [], data.limits.verification)
    return verifyAvailabilityTransfer(expected, request,
      data.wire.toOpenArray(bundle, bundle+parts.lengths[0]-1), [],
      data.wire.toOpenArray(proof, proof+parts.lengths[2]-1), data.limits.verification)
  if parts.lengths[2] == 0:
    return verifyAvailabilityTransfer(expected, request,
      data.wire.toOpenArray(bundle, bundle+parts.lengths[0]-1),
      data.wire.toOpenArray(segments, segments+parts.lengths[1]-1), [], data.limits.verification)
  verifyAvailabilityTransfer(expected, request,
    data.wire.toOpenArray(bundle, bundle+parts.lengths[0]-1),
    data.wire.toOpenArray(segments, segments+parts.lengths[1]-1),
    data.wire.toOpenArray(proof, proof+parts.lengths[2]-1), data.limits.verification)
proc executeAssuranceAcquisition*(job: AssuranceAcquisitionJob,
    control: AssuranceScanControl): AssuranceAcquisitionResult[AssuranceAcquisitionInfo] =
  ## One native lease qualifies the selected parent, verifies every CE137 byte and crosses the real durability boundary before returning fixed progress metadata.
  let data = job.data
  if data == nil: return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.Uninitialized)
  if control.stopped: return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.Cancelled)
  let owner = data.owner
  if not owner[].opened: return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.Closed)
  if owner[].faulted: return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.Faulted)
  if not owner[].matchesChain(data.chain): return refused[AssuranceAcquisitionInfo](
      AssuranceAcquisitionError.WrongChain)
  let qualified = captureAssuranceDuty(data.source, data.local, data.limits.duty)
  if qualified.error != AssuranceDutyError.None:
    return AssuranceAcquisitionResult[AssuranceAcquisitionInfo](
        status: AssuranceAcquisitionError.DutyFailure, dutyReason: qualified)
  let duty = qualified.value
  let requested = duty.shardRequest(data.core, data.ordinal)
  if requested.error != AssuranceDutyError.None:
    return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.InvalidInput)
  let assignment = duty.assignment(data.core).value
  let header = assignment.guarantee.report.ownedReportInfo.value.header
  let expected = AvailabilitySpecifier(packageHash: header.packageHash,
    bundleLength: header.bundleLength,
    erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
    segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)
  let planned = availabilityVerificationInfo(expected, requested.value)
  if planned.error != AvailabilityTransferError.None:
    return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.InvalidInput)
  let work = planned.value
  if work.payloadBytes > 16'u64*1024*1024:
    return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.LimitExceeded)
  let workspace = uint64(data.wire.len)+work.payloadBytes*4+uint64(AssuranceRecordHeaderBytes)*2
  if workspace > uint64(data.limits.workspaceBytes):
    return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.LimitExceeded)
  var parts = default(FrameParts)
  if not frames(data.wire, [work.bundleBytes, work.segmentBytes, work.proofBytes], parts):
    return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.InvalidInput)
  if control.stopped: return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.Cancelled)
  let verified = verify(data, expected, requested.value, parts)
  if verified.error != AvailabilityTransferError.None:
    return AssuranceAcquisitionResult[AssuranceAcquisitionInfo](
        status: AssuranceAcquisitionError.TransferFailure, transferReason: verified)
  if control.stopped: return refused[AssuranceAcquisitionInfo](AssuranceAcquisitionError.Cancelled)
  let stored = owner[].rememberAssuranceShard(verified.value, data.now)
  if stored.error != AssuranceStoreError.None:
    return AssuranceAcquisitionResult[AssuranceAcquisitionInfo](
        status: AssuranceAcquisitionError.StorageFailure, storageReason: stored)
  let record = stored.value.storedInfo
  assert record.error == AssuranceStoreError.None, "sealed successful store receipt has fixed metadata"
  AssuranceAcquisitionResult[AssuranceAcquisitionInfo](status: AssuranceAcquisitionError.None,
    completed: AssuranceAcquisitionInfo(duty: duty.dutyInfo.value, core: data.core,
      validator: duty.localIndex(data.ordinal).value, record: record.value))
