# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assemble a complete canonical work report from one original execution/availability provenance.

import ../../codec/[bounded, composite]
import ../../codec/work/[digest as work_digest, report as work_report]
import ../../chain/parameters
import ../../pvm/host/fetch as host_fetch
import ../availability/specifier as availability_specifier
import "../export/erasure" as export_erasure
import ../bundle_erasure
import ../erasure/layout as erasure_layout
import ../[auditable_bundle, input_refinement]
import ../report/identity as report_identity
import ../authorized_refinement
import ../authorization/invocation as authorization_invocation
import ../refinement/digest as refinement_digest

type
  ComputedReportError* {.pure.} = enum ## Refusals expose no encoded prefix or detached report authority.
    Uninitialized, None, InvalidSource, InvalidReport, LimitExceeded, EncodingFailure
  ComputedReportInfo* = object ## Copied original fixed report fields and exact retained/workspace byte facts.
    header*: ReportHeader
    core*: CoreIndex
    authorizer*: AuthorizerHash
    authorizationGasUsed*: Gas
    prerequisites*, lookupCount*, items*: int
    length*, traceBytes*, blobBytes*, workspaceBytes*: uint64
  ComputedReportData = ref object ## Immutable acyclic ownership retains exact original availability and complete canonical wire.
    source: AvailabilityCommitment
    info: ComputedReportInfo
    wire: seq[byte]
  ComputedWorkReport* = object ## Defaults have no successful report, including no successful empty wire.
    data: nil ComputedReportData
  ComputedReportResult*[T] = object ## Private selected success payloads remain guarded in optimized execution.
    case status: ComputedReportError
    of None:
      completed: T
    else:
      discard # No partially assembled report or caller-visible spans escape refusal.

func error*[T](outcome: ComputedReportResult[T]): ComputedReportError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedReportResult[T]): T
    {.requires: outcome.status == ComputedReportError.None.} =
  ## Extract only a complete successful value.
  outcome.completed
proc computedReportInfo*(report: ComputedWorkReport): ComputedReportResult[ComputedReportInfo] =
  ## Copy fixed report/resource facts without exposing retained canonical storage.
  let data = report.data
  if data == nil: return ComputedReportResult[ComputedReportInfo](
      status: ComputedReportError.Uninitialized)
  ComputedReportResult[ComputedReportInfo](status: ComputedReportError.None, completed: data.info)
proc computedReportSource*(report: ComputedWorkReport): ComputedReportResult[
    AvailabilityCommitment] =
  ## Retain the exact original execution/availability chain rather than accepting later replacements.
  let data = report.data
  if data == nil: return ComputedReportResult[AvailabilityCommitment](
      status: ComputedReportError.Uninitialized)
  ComputedReportResult[AvailabilityCommitment](status: ComputedReportError.None,
      completed: data.source)
proc computedReportBytes*(report: ComputedWorkReport): ComputedReportResult[seq[byte]] =
  ## Return a complete independent canonical byte copy; borrowed decoding belongs to the caller's copy.
  let data = report.data
  if data == nil: return ComputedReportResult[seq[byte]](status: ComputedReportError.Uninitialized)
  var copied = newSeq[byte](data.wire.len)
  for index in 0..<copied.len: copied[index] = data.wire[index]
  ComputedReportResult[seq[byte]](status: ComputedReportError.None, completed: copied)
proc prepareComputedReport*(source: AvailabilityCommitment, limit: ByteLimit): ComputedReportResult[
    ComputedWorkReport] =
  ## Derive fixed metadata and preflight all retained/transient bytes before payload copies or encoding.
  template fail(reason: ComputedReportError) =
    return ComputedReportResult[ComputedWorkReport](status: reason)
  let available = source.availabilityInfo
  if available.error != AvailabilityCommitmentError.None: fail(ComputedReportError.InvalidSource)
  let identity = source.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let facts = identity.identityInfo.value
  let authorized = identity.identitySource.value
  let authorization = authorized.authorizedSource.value
  let original = authorized.authorizedInfo.value
  let digests = authorized.authorizedDigests.value
  let context = facts.context
  let availability = available.value.specifier
  var fields = WorkReport(header: ReportHeader(packageHash: availability.packageHash,
    bundleLength: availability.bundleLength, erasureRoot: availability.erasureRoot,
    erasureShards: availability.erasureShards, segmentRoot: availability.segmentRoot,
    segmentCount: availability.segmentCount, anchor: context.anchor, anchorSlot: context.anchorSlot,
    stateRoot: context.stateRoot, accumulationRoot: context.accumulationRoot,
    lookupAnchor: context.lookupAnchor,
    lookupSlot: context.lookupSlot, lookupStateRoot: context.lookupStateRoot),
    prerequisites: context.prerequisites, prerequisiteCount: context.prerequisiteCount,
    core: facts.core, authorizer: facts.authorizer, authGas: facts.authorizationGasUsed,
    lookupCount: facts.lookupCount, digestCount: digests.digestCount.value)
  if original.blobBytes > 49152 or original.traceBytes > original.blobBytes: fail(
      ComputedReportError.InvalidReport)
  fields.authOutput = BlobSpan(offset: 0, length: int(original.traceBytes))
  for index in 0..<fields.lookupCount: fields.lookup[index] = identity.identityLookupAt(
      ReportLookupIndex(uint64(index))).value
  var cursor = int(original.traceBytes)
  var largest = original.traceBytes
  # Only final Success outputs receive private pool spans; every error alternative remains payload-free.
  for index in 0..<fields.digestCount:
    let info = digests.digestAt(FetchItemIndex(uint64(index))).value.digestInfo.value
    if info.outputBytes > 49152-uint64(cursor): fail(ComputedReportError.InvalidReport)
    let kind = if info.kind == WorkKind.Success:
      successfulWork(BlobSpan(offset: cursor, length: int(info.outputBytes)))
    else:
      failedWork(info.kind)
    fields.digests[index] = WorkDigest(service: info.service, codeHash: info.codeHash,
      payloadHash: info.payloadHash, accumulateGas: info.accumulateGas, output: kind,
      refine: info.refine)
    cursor += int(info.outputBytes) # The shared-ceiling subtraction proves addition and native indexing first.
    largest = max(largest, info.outputBytes)
  if uint64(cursor) != original.blobBytes: fail(ComputedReportError.InvalidReport)
  let cores = authorization.authorizationParameters.value.get(coreCount)
  let measured = measureReportBorrowed(fields, cursor, cores)
  if measured.error != CompositeError.None: fail(ComputedReportError.InvalidReport)
  let length = uint64(measured.written)
  let workspace = original.blobBytes+largest # Shared payload <=49152 bounds this addition below 98305.
  if length > uint64(limit): fail(ComputedReportError.LimitExceeded)
  if workspace > uint64(limit)-length: fail(ComputedReportError.LimitExceeded)
  var pool = newSeq[byte](cursor)
  block:
    # Retire the independent authorization copy before extracting any per-item output copy.
    let trace = authorization.authorizationTrace.value
    for position in 0..<trace.len: pool[position] = trace[position]
  var offset = int(original.traceBytes)
  for index in 0..<fields.digestCount:
    if fields.digests[index].output.kind == WorkKind.Success:
      let bytes = digests.digestAt(FetchItemIndex(uint64(index))).value.digestOutput.value
      for octet in bytes:
        pool[offset] = octet
        inc offset
  if offset != pool.len: fail(ComputedReportError.EncodingFailure) # Never publish an incomplete private payload pool.
  var wire = newSeq[byte](measured.written)
  let encoded = encodeReportBorrowed(fields, pool, cores, wire)
  if encoded.error != CompositeError.None: fail(ComputedReportError.EncodingFailure)
  if encoded.written != wire.len: fail(ComputedReportError.EncodingFailure)
  ComputedReportResult[ComputedWorkReport](status: ComputedReportError.None,
    completed: ComputedWorkReport(data: ComputedReportData(source: source, wire: wire,
      info: ComputedReportInfo(header: fields.header, core: fields.core,
        authorizer: fields.authorizer,
        authorizationGasUsed: fields.authGas, prerequisites: fields.prerequisiteCount,
        lookupCount: fields.lookupCount, items: fields.digestCount, length: length,
        traceBytes: original.traceBytes,
        blobBytes: original.blobBytes, workspaceBytes: workspace))))
