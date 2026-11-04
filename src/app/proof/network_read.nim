# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable admitted network read jobs. Moving a job to the CPU worker requires the same
## exclusive ARC graph lease as proof queries; cancellation releases it only on collection/join.
import ../../chain/[provider, genesis]
import ../../codec/bounded
import ../../jamnp-s/[read_stream, canonical_read, availability_read]
import ../../state/availability/specifier

type
  NetworkReadData = ref object ## One acyclic retained canonical view and copied fixed request survive worker handoff.
    view: ChainView
    request: ReadRequest
    availability: bool
    source: AvailabilityCommitment
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
    view: projected.value, request: request))) # The optional unbounded memory-history index is not retained.
proc captureAvailabilityRead*(source: AvailabilityCommitment, request: ReadRequest,
    limits: AvailabilityReadLimits): NetworkReadAdmission =
  ## The caller retires every temporary alias before submitting the existing exclusive canonical lease.
  if not limits.valid: return NetworkReadAdmission(status: ReadError.LimitExceeded)
  if not request.availabilityRead: return NetworkReadAdmission(status: ReadError.InvalidRequest)
  let described = source.availabilityInfo
  if described.error != AvailabilityCommitmentError.None: return NetworkReadAdmission(
      status: ReadError.Unavailable)
  if not request.matchesAvailability(described.value.specifier): return NetworkReadAdmission(
      status: ReadError.Unavailable)
  NetworkReadAdmission(status: ReadError.None, completed: NetworkReadJob(data: NetworkReadData(
    availability: true, source: source, request: request, limits: limits)))
proc executeNetworkRead*(job: NetworkReadJob): ReadResult[ReadReply] =
  ## Only the worker touches the admitted source graph during the exclusive lease.
  let data = job.data
  if data == nil: return readFailure[ReadReply](ReadError.InvalidRequest)
  if data.availability: serveAvailabilityRead(data.source, data.request, data.limits)
  else: serveCanonicalRead(data.view, data.request)
