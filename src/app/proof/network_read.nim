# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable admitted network read jobs. Moving a job to the CPU worker requires the same
## exclusive ARC graph lease as proof queries; cancellation releases it only on collection/join.

import std/algorithm
import ../../chain/[provider, genesis]
import ../../codec/bounded
import ../../jamnp-s/[read_stream, canonical_read, availability_read, segment_request]
import ../../state/availability/specifier
import ../../state/erasure/words
import ../../jamnp-s/[availability_proof, assurance_store, assurance_record]

type
  AssuranceReadLimits* = object ## Durable root recovery and later reply derivation have separate explicit workspace, proof and wire ceilings; omission enables neither.
    restore*: AssuranceRestoreLimits
    reply*: AvailabilityReadLimits
    batchSources*: ElementLimit
  StoredRestore = object ## A failed private restore carries only its read error, never a source or record alias.
    case status: ReadError
    of None: transfer: VerifiedAvailabilityTransfer
    else: discard # Only a successful complete stored verification and detached copy grants a serving source.
  ShardRestore = object ## A late failure cannot expose a successfully restored prefix of a batch.
    case status: ReadError
    of None:
      sources: seq[VerifiedAvailabilityTransfer]
      payloadBytes, metadataBytes: uint64
    else: discard       # All intermediate verified payloads retire before a failed result escapes.
  NetworkSource {.pure.} = enum ## Only module-owned capture chooses an original canonical/report/assurer source.
    Canonical, Computed, Retained, OriginalSegments, Assured, ShardBatch, DurableAssured
  NetworkReadData = ref object ## One privately selected source or exclusive namespace borrow and copied bounded request survive worker handoff.
    view: ChainView
    request: ReadRequest
    kind: NetworkSource
    stored: VerifiedAvailabilityTransfer
    snapshot: seq[VerifiedAvailabilityTransfer]
    source: AvailabilityCommitment
    retained: GuarantorAvailability
    retainedSources: seq[GuarantorAvailability]
    limits: AvailabilityReadLimits
    archive: nil ptr AssuranceStore
    restore: AssuranceRestoreLimits
    batchSources: ElementLimit
  NetworkReadJob* = object ## Default jobs contain neither a canonical source nor an admitted request.
    data: nil NetworkReadData
  NetworkReadAdmission* = object ## Guarded capture exposes a complete job or only its refusal reason.
    case status: ReadError
    of None: completed: NetworkReadJob
    else: discard # Failed captures never retain an oversized graph.

func error*(outcome: NetworkReadAdmission): ReadError =
  ## Inspect admission without accessing a partial source.
  outcome.status

func value*(outcome: NetworkReadAdmission): NetworkReadJob {.requires: outcome.status ==
    ReadError.None.} =
  ## Extract only the complete immutable job.
  outcome.completed

func valid*(job: NetworkReadJob): bool =
  ## Default jobs cannot claim a worker lease.
  job.data != nil

func valid*(limits: AssuranceReadLimits): bool =
  ## Default policies cannot perform fixed-header IO or derive any reply.
  limits.restore.valid and limits.reply.valid and uint64(limits.batchSources) <= 6144

proc captureAssuranceRead*(owner: var AssuranceStore, request: ReadRequest,
    limits: AssuranceReadLimits): NetworkReadAdmission =
  ## Borrow only this fixed owner address and copied bounded request; the caller freezes the namespace until exact collection or joined stop.
  if not limits.valid: return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if not request.valid or request.kind notin [ReadKind.Audit, ReadKind.SegmentShards,
      ReadKind.ProvenSegmentShards]: return NetworkReadAdmission(status: ReadError.InvalidRequest)
  if request.kind != ReadKind.Audit and uint64(limits.batchSources) == 0:
    return NetworkReadAdmission(status: ReadError.Unavailable)
  if uint64(request.payloadLength)*2 > uint64(limits.restore.workspaceBytes):
    return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if not owner.opened or owner.faulted: return NetworkReadAdmission(status: ReadError.Unavailable)
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    kind: NetworkSource.DurableAssured, archive: addr owner, restore: limits.restore,
    batchSources: limits.batchSources, request: detachedReadRequest(request),
        limits: limits.reply)))

proc captureNetworkRead*(view: ChainView, request: ReadRequest): NetworkReadAdmission =
  ## Bound the retained view before copying its indexes; callers keep all aliases frozen until retirement.
  if view.fuzzOnly: return NetworkReadAdmission(status: ReadError.InvalidRequest) # Test-only origin never grants an ordinary network source.
  if not request.valid: return NetworkReadAdmission(status: ReadError.InvalidRequest)
  if view.retainedCount == 0: return NetworkReadAdmission(status: ReadError.Unavailable)
  if view.retainedCount > 64: return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if view.viewRetentionInfo.bytes > 32'u64*1024*1024: return NetworkReadAdmission(
      status: ReadError.LimitExceeded)
  var history: seq[BlockSnapshotResult] = @[]
  for index in 0..<view.retainedCount:
    history.add(view.retainedBlockAt(RetainedBlockIndex(index))) # Copy only the admitted rolling window.
  let projected = restoreLocalChainView(history, view.finalizedBlock, ElementLimit(64))
  if projected.error != ViewAdvanceError.None: return NetworkReadAdmission(
      status: ReadError.InvalidRequest)
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    view: projected.value, request: detachedReadRequest(
        request)))) # The optional unbounded memory-history index is not retained.

proc captureAvailabilityRead*(source: AvailabilityCommitment, request: ReadRequest,
    limits: AvailabilityReadLimits): NetworkReadAdmission =
  ## The caller retires every temporary alias before submitting the existing exclusive canonical lease.
  if not limits.valid: return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if not request.availabilityRead and (not request.valid or request.kind !=
      ReadKind.Segments): return NetworkReadAdmission(status: ReadError.InvalidRequest)
  let described = source.availabilityInfo
  if described.error != AvailabilityCommitmentError.None: return NetworkReadAdmission(
      status: ReadError.Unavailable)
  if request.kind != ReadKind.Segments and not request.matchesAvailability(
      described.value.specifier): return NetworkReadAdmission(status: ReadError.Unavailable)
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    kind: NetworkSource.Computed, source: source, request: detachedReadRequest(request),
        limits: limits)))

proc captureAvailabilityRead*(source: GuarantorAvailability, request: ReadRequest,
    limits: AvailabilityReadLimits): NetworkReadAdmission =
  ## Only a Services-owned retained root crosses this lease; no completed work session or canonical map is required.
  if not limits.valid: return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if not request.availabilityRead: return NetworkReadAdmission(status: ReadError.InvalidRequest)
  let described = source.guarantorInfo
  if described.error != AvailabilityTransferError.None:
    return NetworkReadAdmission(status: ReadError.Unavailable)
  if not request.matchesAvailability(described.value.specifier):
    return NetworkReadAdmission(status: ReadError.Unavailable)
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    kind: NetworkSource.Retained, retained: source, request: detachedReadRequest(request),
        limits: limits)))

proc captureOriginalSegments*(original: AvailabilityCommitment,
    sources: openArray[GuarantorAvailability], request: ReadRequest,
    limits: AvailabilityReadLimits): NetworkReadAdmission =
  ## Freeze the complete private source table plus optional unsigned original before managed multi-root selection and proof work.
  if not limits.valid or sources.len > 64: return NetworkReadAdmission(
      status: ReadError.LimitExceeded)
  if not request.valid or request.kind != ReadKind.Segments:
    return NetworkReadAdmission(status: ReadError.InvalidRequest)
  var retained = newSeq[GuarantorAvailability](sources.len)
  for index in 0..<sources.len: retained[index] = sources[index]
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    kind: NetworkSource.OriginalSegments, source: original, retainedSources: retained,
    request: detachedReadRequest(request), limits: limits)))

proc captureAvailabilityAudit*(source: VerifiedAvailabilityTransfer, request: ReadRequest,
    limits: AvailabilityReadLimits): NetworkReadAdmission =
  ## Services keeps the private cache frozen through exact collection; no external caller alias is retained by the store.
  if not limits.valid: return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if not request.valid or request.kind != ReadKind.Audit: return NetworkReadAdmission(
      status: ReadError.InvalidRequest)
  if not source.valid or source.request.kind != AvailabilityTransferKind.Distribution:
    return NetworkReadAdmission(status: ReadError.Unavailable)
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    kind: NetworkSource.Assured, stored: source, request: detachedReadRequest(request),
        limits: limits)))

proc captureSegmentShardBatch*(sources: openArray[VerifiedAvailabilityTransfer],
    request: ReadRequest, limits: AvailabilityReadLimits): NetworkReadAdmission =
  ## Only Services-owned immutable cache entries cross the lease; external/native request bytes are detached before submission.
  if not limits.valid or sources.len > 64: return NetworkReadAdmission(
      status: ReadError.LimitExceeded)
  if not request.valid or request.kind notin [ReadKind.SegmentShards, ReadKind.ProvenSegmentShards]:
    return NetworkReadAdmission(status: ReadError.InvalidRequest)
  var snapshot = newSeq[VerifiedAvailabilityTransfer](sources.len)
  for index in 0..<sources.len: snapshot[index] = sources[index]
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    kind: NetworkSource.ShardBatch, snapshot: snapshot, request: detachedReadRequest(request),
        limits: limits)))

proc restoreDistribution(archive: nil ptr AssuranceStore, selected: AvailabilityRequest,
    limits: AssuranceRestoreLimits): StoredRestore =
  ## The intermediate record owner retires before its detached source can participate in later reply allocations.
  if archive == nil: return StoredRestore(status: ReadError.Unavailable)
  let stored = archive[].restoreAssuranceShard(selected, limits)
  if stored.error in [AssuranceStoreError.LimitExceeded, AssuranceStoreError.InvalidPolicy]:
    return StoredRestore(status: ReadError.LimitExceeded)
  if stored.error != AssuranceStoreError.None: return StoredRestore(status: ReadError.Unavailable)
  let copied = stored.value.storedTransfer(ByteLimit(uint64(limits.workspaceBytes) div 2))
  if copied.error == AvailabilityTransferError.LimitExceeded: return StoredRestore(
      status: ReadError.LimitExceeded)
  if copied.error != AvailabilityTransferError.None: return StoredRestore(
      status: ReadError.Unavailable)
  StoredRestore(status: ReadError.None, transfer: copied.value)

func compareRestoreLocations(left, right: SegmentSelection): int =
  ## Sorting private copied coordinates restores each root/shard once without changing the original request or reply order.
  for index in 0..<32:
    if left.root[index] < right.root[index]: return -1
    if left.root[index] > right.root[index]: return 1
  if left.shard < right.shard: return -1
  if left.shard > right.shard: return 1
  0

proc restoreShardSources(data: NetworkReadData, control: AssuranceScanControl): ShardRestore =
  ## Whole-request restore work and resident payloads remain bounded across every original record; a later refusal releases the entire private snapshot.
  let count = data.request.itemCount
  let capacity = min(count, int(uint64(data.batchSources)))
  let metadata = uint64(count)*128+uint64(capacity)*32+uint64(data.request.payloadLength)*2
  let workspace = uint64(data.restore.workspaceBytes)
  if metadata > workspace: return ShardRestore(status: ReadError.LimitExceeded)
  let parsed = segmentSelections(data.request.kind.segmentKind, data.request.payload)
  if parsed.error != SegmentRequestError.None: return ShardRestore(status: ReadError.InvalidRequest)
  var selected = parsed.value
  selected.sort(compareRestoreLocations)
  var sources = newSeq[VerifiedAvailabilityTransfer](capacity)
  var used = 0
  var resident = 0'u64
  var remaining = data.restore
  for ordinal, item in selected:
    # Duplicate rows and groups retain their eventual reply positions but require no second record read or restored payload graph.
    if ordinal > 0 and compareRestoreLocations(selected[ordinal-1], item) == 0: continue
    if control.stopped: return ShardRestore(status: ReadError.Unavailable)
    if used >= capacity: return ShardRestore(status: ReadError.LimitExceeded)
    if resident > workspace-metadata: return ShardRestore(status: ReadError.LimitExceeded)
    var exact = remaining
    exact.workspaceBytes = ByteLimit(workspace-metadata-resident)
    var request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
      shard: ErasureShardIndex(uint64(item.shard)))
    request.root.bytes = item.root
    let restored = restoreDistribution(data.archive, request, exact)
    if control.stopped: return ShardRestore(status: ReadError.Unavailable)
    if restored.status != ReadError.None: return ShardRestore(status: restored.status)
    let transfer = restored.transfer
    let described = availabilityVerificationInfo(transfer.specifier, transfer.request)
    if described.error != AvailabilityTransferError.None: return ShardRestore(
        status: ReadError.Unavailable)
    let work = described.value
    let io = work.payloadBytes+uint64(AssuranceRecordHeaderBytes)*2+1
    let hashes = work.hashes+2
    let hashBytes = work.hashBytes+348
    if io > uint64(remaining.ioBytes) or hashes > uint64(remaining.verification.hashes):
      return ShardRestore(status: ReadError.LimitExceeded)
    if hashBytes > uint64(remaining.verification.hashBytes) or work.payloadBytes >
        workspace-metadata-resident:
      return ShardRestore(status: ReadError.LimitExceeded)
    remaining.ioBytes = ByteLimit(uint64(remaining.ioBytes)-io)
    remaining.verification.hashes = ElementLimit(uint64(remaining.verification.hashes)-hashes)
    remaining.verification.hashBytes = ByteLimit(uint64(remaining.verification.hashBytes)-hashBytes)
    resident += work.payloadBytes
    sources[used] = transfer
    inc used
  sources.setLen(used)
  ShardRestore(status: ReadError.None, sources: move(sources), payloadBytes: resident,
    metadataBytes: uint64(capacity)*16)

proc serveDurableShards(data: NetworkReadData, control: AssuranceScanControl): ReadResult[ReadReply] =
  ## Only a whole restored snapshot reaches ordinary ordered row/proof construction; freshly allocated resident source graphs remain charged during the reply phase.
  let restored = restoreShardSources(data, control)
  if restored.status != ReadError.None: return readFailure[ReadReply](restored.status)
  let resident = restored.payloadBytes+restored.metadataBytes
  if resident > uint64(data.limits.computation.bytes): return readFailure[ReadReply](
      ReadError.LimitExceeded)
  var limits = data.limits
  limits.computation.bytes = ByteLimit(uint64(limits.computation.bytes)-resident)
  if control.stopped: return readFailure[ReadReply](ReadError.Unavailable)
  let reply = serveSegmentShardBatch(restored.sources, data.request, limits)
  if control.stopped: return readFailure[ReadReply](ReadError.Unavailable)
  reply

proc serveDurableAudit(data: NetworkReadData, control: AssuranceScanControl): ReadResult[ReadReply] =
  ## Full original-distribution verification and synchronization precede existing bounded two-frame audit derivation, with no namespace alias in the response.
  if control.stopped: return readFailure[ReadReply](ReadError.Unavailable)
  let payload = data.request.payload
  var selected = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
    shard: ErasureShardIndex(uint64(payload[32]) or (uint64(payload[33]) shl 8)))
  for index in 0..<32: selected.root.bytes[index] = payload[index]
  let restored = restoreDistribution(data.archive, selected, data.restore)
  if control.stopped: return readFailure[ReadReply](ReadError.Unavailable)
  if restored.status != ReadError.None: return readFailure[ReadReply](restored.status)
  let reply = serveAvailabilityAudit(restored.transfer, data.request, data.limits)
  if control.stopped: return readFailure[ReadReply](ReadError.Unavailable)
  reply

proc executeNetworkRead*(job: NetworkReadJob, control = default(AssuranceScanControl)): ReadResult[ReadReply] =
  ## Only the worker touches the admitted source graph during the exclusive lease.
  let data = job.data
  if data == nil: return readFailure[ReadReply](ReadError.InvalidRequest)
  if control.stopped: return readFailure[ReadReply](ReadError.Unavailable)
  case data.kind
  of NetworkSource.Computed:
    if data.request.kind == ReadKind.Segments: serveOriginalSegmentBatch(data.source, data.request, data.limits)
    else: serveAvailabilityRead(data.source, data.request, data.limits)
  of NetworkSource.Retained: serveAvailabilityRead(data.retained, data.request, data.limits)
  of NetworkSource.OriginalSegments:
    serveRetainedSegmentBatch(data.retainedSources, data.source, data.request, data.limits)
  of NetworkSource.ShardBatch: serveSegmentShardBatch(data.snapshot, data.request, data.limits)
  of NetworkSource.Assured: serveAvailabilityAudit(data.stored, data.request, data.limits)
  of NetworkSource.DurableAssured:
    if data.request.kind == ReadKind.Audit: serveDurableAudit(data, control)
    else: serveDurableShards(data, control)
  of NetworkSource.Canonical: serveCanonicalRead(data.view, data.request)
