# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable admitted network read jobs. Moving a job to the CPU worker requires the same
## exclusive ARC graph lease as proof queries; cancellation releases it only on collection/join.
import ../../chain/[provider, genesis]
import ../../codec/bounded
import ../../jamnp-s/[read_stream, canonical_read, availability_read]
import ../../state/availability/specifier
import ../../jamnp-s/availability_proof

type
  NetworkSource {.pure.} = enum ## Only module-owned capture chooses an original canonical/report/assurer source.
    Canonical, Computed, Retained, OriginalSegments, Assured, ShardBatch
  NetworkReadData = ref object ## One privately selected immutable source and copied fixed request survive worker handoff.
    view: ChainView
    request: ReadRequest
    kind: NetworkSource
    stored: VerifiedAvailabilityTransfer
    snapshot: seq[VerifiedAvailabilityTransfer]
    source: AvailabilityCommitment
    retained: GuarantorAvailability
    retainedSources: seq[GuarantorAvailability]
    limits: AvailabilityReadLimits
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
proc executeNetworkRead*(job: NetworkReadJob): ReadResult[ReadReply] =
  ## Only the worker touches the admitted source graph during the exclusive lease.
  let data = job.data
  if data == nil: return readFailure[ReadReply](ReadError.InvalidRequest)
  case data.kind
  of NetworkSource.Computed:
    if data.request.kind == ReadKind.Segments: serveOriginalSegmentBatch(data.source, data.request, data.limits)
    else: serveAvailabilityRead(data.source, data.request, data.limits)
  of NetworkSource.Retained: serveAvailabilityRead(data.retained, data.request, data.limits)
  of NetworkSource.OriginalSegments:
    serveRetainedSegmentBatch(data.retainedSources, data.source, data.request, data.limits)
  of NetworkSource.ShardBatch: serveSegmentShardBatch(data.snapshot, data.request, data.limits)
  of NetworkSource.Assured: serveAvailabilityAudit(data.stored, data.request, data.limits)
  of NetworkSource.Canonical: serveCanonicalRead(data.view, data.request)
