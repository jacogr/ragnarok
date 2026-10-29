# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute original package items in order and apply GP I's shared blob/export result rules.
## Immutable results retain provenance; authorization, availability and state publication are separate.

import ../../codec/[bounded, composite]
import ../../codec/work/[package as work_package, digest as work_digest, report as work_report]
import ../../chain/parameters
import ../../pvm/[host_fetch, refinement_exports]
import ../store
import ./[bootstrap as refinement_bootstrap, outcome as refinement_outcome,
    dispatch as refinement_dispatch]

type
  RefinementReportError* {.pure.} = enum ## Local refusals carry no partial item prefix or fabricated protocol result.
    Uninitialized, None, InvalidPackage, InvalidTrace, LimitExceeded, InvalidIndex, NotSuccess,
    BootstrapFailure, InvocationFailure
  RefinementReportLimits* = object ## Aggregate retention caps supplement finite per-item preparation/execution policies.
    items*, exports*: ElementLimit
    blobs*: ByteLimit
    bootstrap*: RefinementBootstrapLimits
    invocation*: RefinementInvocationLimits
  RefinedItemInfo* = object ## Copied normalized result facts cannot rebind source or replace the selected execution result.
    kind*: WorkKind
    service*: ServiceIndex
    gasUsed*: Gas
    item*: FetchItemIndex
    offset*: ExportOffset
    exports*: ExportCount
    outputBytes*: uint64
  RefinedItemData = ref object ## Immutable acyclic selection retains its actual source and only accepted output/export storage.
    source: OwnedWorkItem
    exports: RefinementExports
    info: RefinedItemInfo
    case hasOutput: bool
    of true:
      bytes: seq[byte]
    of false:
      discard # Rejected invocation bytes and actual exports are retired before the next item.
  RefinedWorkItem* = object ## Default has no item; a genuine empty Success has an explicit owner.
    data: nil RefinedItemData
  RefinementReportInfo* = object ## Aggregate blob size counts trace plus only the final successful outputs.
    items*: int
    exports*: ExportCount
    blobBytes*: uint64
    core*: CoreIndex
  RefinementReportData = ref object ## One completed owner retains exact source package, trace and ordered final items.
    package: OwnedWorkPackage
    trace: seq[byte]
    items: seq[RefinedWorkItem]
    info: RefinementReportInfo
  RefinedPackage* = object ## This is the refinement portion of a report, without an availability/publication certificate.
    data: nil RefinementReportData
  RefinementReportResult*[T] = object ## Private alternatives expose only complete success or the selected local reason.
    case status: RefinementReportError
    of None:
      completed: T
    of BootstrapFailure:
      bootstrapReason: RefinementBootstrapError
    of InvocationFailure:
      invocationReason: RefinementInvocationResult[RefinementInvocation]
    else:
      discard # Default/local refusals contain no partial owner or misleading stage detail.

func error*[T](outcome: RefinementReportResult[T]): RefinementReportError =
  ## Inspect a read-only discriminator.
  outcome.status
func value*[T](outcome: RefinementReportResult[T]): T
    {.requires: outcome.status == RefinementReportError.None.} =
  ## Extract only the complete selected result.
  outcome.completed
func bootstrapError*[T](outcome: RefinementReportResult[T]): RefinementBootstrapError
    {.requires: outcome.status == RefinementReportError.BootstrapFailure.} =
  ## Preserve the exact preparation refusal without inventing an invocation error.
  outcome.bootstrapReason
func invocationError*[T](outcome: RefinementReportResult[T]): RefinementInvocationResult[RefinementInvocation]
    {.requires: outcome.status == RefinementReportError.InvocationFailure.} =
  ## Retain the failed invocation alternative, including its guarded host/engine/capture detail.
  outcome.invocationReason

proc reportInfo*(report: RefinedPackage): RefinementReportResult[RefinementReportInfo] =
  ## Copy aggregate facts only from a complete ordered result.
  let data = report.data
  if data == nil: return RefinementReportResult[RefinementReportInfo](
      status: RefinementReportError.Uninitialized)
  RefinementReportResult[RefinementReportInfo](status: RefinementReportError.None,
      completed: data.info)
proc reportPackage*(report: RefinedPackage): RefinementReportResult[OwnedWorkPackage] =
  ## Retain the original immutable package for subsequent source-bound digest construction.
  let data = report.data
  if data == nil: return RefinementReportResult[OwnedWorkPackage](
      status: RefinementReportError.Uninitialized)
  RefinementReportResult[OwnedWorkPackage](status: RefinementReportError.None,
      completed: data.package)
proc reportTrace*(report: RefinedPackage): RefinementReportResult[seq[byte]] =
  ## Return an independent copy of the exact trace used for this result.
  let data = report.data
  if data == nil: return RefinementReportResult[seq[byte]](
      status: RefinementReportError.Uninitialized)
  var copied = newSeq[byte](data.trace.len)
  for index in 0..<copied.len: copied[index] = data.trace[index] # Never expose writable retained storage.
  RefinementReportResult[seq[byte]](status: RefinementReportError.None, completed: copied)
proc reportItem*(report: RefinedPackage, index: FetchItemIndex): RefinementReportResult[
    RefinedWorkItem] =
  ## Validate the full-width nominal index before narrowing to the bounded sequence extent.
  let data = report.data
  if data == nil: return RefinementReportResult[RefinedWorkItem](
      status: RefinementReportError.Uninitialized)
  if uint64(index) >= uint64(data.items.len):
    return RefinementReportResult[RefinedWorkItem](status: RefinementReportError.InvalidIndex)
  RefinementReportResult[RefinedWorkItem](status: RefinementReportError.None, completed: data.items[
      int(uint64(index))])
proc refinedInfo*(item: RefinedWorkItem): RefinementReportResult[RefinedItemInfo] =
  ## Copy normalized item facts without exposing writable result storage or source handles.
  let data = item.data
  if data == nil: return RefinementReportResult[RefinedItemInfo](
      status: RefinementReportError.Uninitialized)
  RefinementReportResult[RefinedItemInfo](status: RefinementReportError.None, completed: data.info)
proc refinedSource*(item: RefinedWorkItem): RefinementReportResult[OwnedWorkItem] =
  ## Keep source extraction bound to this exact item's original owned package.
  let data = item.data
  if data == nil: return RefinementReportResult[OwnedWorkItem](
      status: RefinementReportError.Uninitialized)
  RefinementReportResult[OwnedWorkItem](status: RefinementReportError.None, completed: data.source)
proc refinedOutput*(item: RefinedWorkItem): RefinementReportResult[seq[byte]] =
  ## Only final Success exposes an independent copy; rejected raw outputs never become report blobs.
  let data = item.data
  if data == nil: return RefinementReportResult[seq[byte]](
      status: RefinementReportError.Uninitialized)
  if not data.hasOutput:
    return RefinementReportResult[seq[byte]](status: RefinementReportError.NotSuccess)
  var copied = newSeq[byte](data.bytes.len)
  for index in 0..<copied.len: copied[index] = data.bytes[index] # No mutable alias to accepted bytes escapes.
  RefinementReportResult[seq[byte]](status: RefinementReportError.None, completed: copied)
proc refinedSegment*(item: RefinedWorkItem, index: ExportCount): RefinementReportResult[FetchSegment] =
  ## Synthesize protocol zero replacements lazily, bounded by the original declaration rather than caller sizes.
  let data = item.data
  if data == nil: return RefinementReportResult[FetchSegment](
      status: RefinementReportError.Uninitialized)
  if uint64(index) >= uint64(data.info.exports):
    return RefinementReportResult[FetchSegment](status: RefinementReportError.InvalidIndex)
  let segment = if data.info.kind == WorkKind.Success:
    data.exports.segment(index)
  else:
    default(FetchSegment) # Every report error replaces exactly the declared segment count with zeros.
  RefinementReportResult[FetchSegment](status: RefinementReportError.None, completed: segment)

proc refinePackage*(state: StateStoreSnapshot, package: OwnedWorkPackage, core: CoreIndex,
    parameters: Parameters, trace: openArray[byte], inputs: RefinementInputs,
    limits: RefinementReportLimits): RefinementReportResult[RefinedPackage] =
  ## Borrow trace/input descriptions synchronously; publish only after every original item completes locally.
  template fail(reason: RefinementReportError) =
    return RefinementReportResult[RefinedPackage](status: reason)
  let described = package.workPackageInfo
  if described.error != PackageError.None: fail(RefinementReportError.InvalidPackage)
  if trace.len > 49152: fail(RefinementReportError.InvalidTrace) # Fixed Cmaxreportvarsize is independent of local caps.
  let count = described.value.items
  if uint64(count) > uint64(limits.items) or uint64(trace.len) > uint64(limits.blobs):
    fail(RefinementReportError.LimitExceeded) # Bound even trace copying and result metadata before allocation.
  var declared = 0'u64
  for index in 0..<count:
    let info = package.workItemAt(index).value.workItemInfo.value
    if uint64(info.exports) > 3072-declared: fail(RefinementReportError.InvalidPackage)
    declared += uint64(info.exports) # Decoder and explicit subtraction prove the aggregate package bound.
  if declared > uint64(limits.exports): fail(RefinementReportError.LimitExceeded)
  var savedTrace = newSeq[byte](trace.len)
  for index in 0..<trace.len: savedTrace[index] = trace[
      index] # Isolate future extraction from borrowed caller storage.
  var items = newSeqOfCap[RefinedWorkItem](count)
  var offset = 0'u64
  var blobs = uint64(trace.len)
  for index in 0..<count:
    let source = package.workItemAt(index).value
    let declaration = source.workItemInfo.value
    let bootstrap = prepareRefinementBootstrap(state, package, FetchItemIndex(uint64(index)), core,
        parameters, limits.bootstrap)
    if bootstrap.error != RefinementBootstrapError.None:
      return RefinementReportResult[RefinedPackage](status: RefinementReportError.BootstrapFailure,
        bootstrapReason: bootstrap.error) # Discard the entire private prefix on late preparation failure.
    let invoked = runRefinementInvocation(bootstrap.value, trace, inputs, ExportOffset(offset),
        limits.invocation)
    if invoked.error != RefinementInvocationError.None:
      return RefinementReportResult[RefinedPackage](status: RefinementReportError.InvocationFailure,
        invocationReason: invoked) # Preserve exact nested reasons without any partial report owner.
    let invocation = invoked.value
    let raw = invocation.refinementInfo.value
    var kind = raw.kind
    if raw.outputBytes > 49152-blobs:
      kind = WorkKind.Oversize # Oversize wins even when actual and declared exports differ.
    elif uint64(raw.exports) != uint64(declaration.exports):
      kind = WorkKind.BadExports # Mismatch wins over an invocation work error as prescribed by I.
    var size = 0'u64
    if kind == WorkKind.Success:
      size = raw.outputBytes # Only accepted Success contributes to the ordered shared blob counter.
      if blobs > uint64(limits.blobs) or size > uint64(limits.blobs)-blobs:
        fail(RefinementReportError.LimitExceeded) # Local retention refusal cannot become protocol Oversize.
      blobs += size # Protocol and local subtraction bounds prove addition before mutation.
    let facts = RefinedItemInfo(kind: kind, service: raw.service, gasUsed: raw.gasUsed,
      item: raw.item, offset: ExportOffset(offset), exports: declaration.exports, outputBytes: size)
    let selected = if kind == WorkKind.Success:
      RefinedItemData(source: source, info: facts, hasOutput: true,
        bytes: invocation.refinementOutput.value, exports: invocation.refinementExports.value)
    else:
      RefinedItemData(source: source, info: facts, hasOutput: false,
        exports: captureRefinementExports(ExportOffset(
            offset))) # Retire rejected payloads; synthesize zeros only on extraction.
    items.add(RefinedWorkItem(data: selected))
    offset += uint64(declaration.exports) # Preflight proved the full declared sum <=3072, including failed items.
  RefinementReportResult[RefinedPackage](status: RefinementReportError.None,
    completed: RefinedPackage(data: RefinementReportData(package: package, trace: savedTrace,
      items: items, info: RefinementReportInfo(items: count, exports: ExportCount(offset),
        blobBytes: blobs, core: core))))
