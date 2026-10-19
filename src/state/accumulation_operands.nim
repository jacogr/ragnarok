# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accumulation.tex operandtuple/accone: report-derived per-service operand preparation.
##
## Exposes explicit report ranges, bounded preparation, immutable service-group/operand access
## and a block-bound adapter retaining the queue certificate. Execution/gas allocation are separate.

import std/algorithm
import ../codec/[bounded, natural, composite, work_digest, report_owned, owned, c2_records]
import ./accumulation_queue

type
  AccumulationReportStart* = distinct uint64 ## Original-queue range start is distinct from a selected report count.
  AccumulationReportPrefix* = distinct uint64 ## A caller-selected prefix is not an executed-report count or a byte/digest ordinal.
  OperandServiceIndex* = distinct uint64 ## A service-group ordinal is not the protocol service identifier stored at that position.
  ServiceOperandIndex* = distinct uint64 ## A per-service operand ordinal cannot address a service group or report queue.
  AccumulationOperandConfig* = object ## Independent local ceilings bound traversal, descriptors, copied payloads and retained operand wire.
    reports*, operands*, services*: ElementLimit
    totalBlobBytes*, totalBytes*: ByteLimit
    operand*: OperandLimits
  AccumulationOperandError* {.pure.} = enum ## Default/refused alternatives expose no partial service group, input sequence or copied progress.
    Uninitialized, None, InvalidConfig, InvalidQueue, InvalidPrefix, LimitExceeded,
    InvalidOperand, InvalidIndex
  ## Private preflight descriptor retains its exact report and stable report/digest traversal order.
  Descriptor = object
    report: OwnedReport
    service: ServiceIndex
    digest, order, wireBytes, outputBytes, authBytes: int
  ## Private immutable group contains only complete independently retained C.2 operand owners.
  ServiceGroup = object
    service: ServiceIndex
    operands: seq[OwnedOperand]
  ## Acyclic owner retains source provenance, the explicit prefix and sorted service groups.
  OperandData = ref object
    source: AccumulationQueuePlan
    prefix: AccumulationReportPrefix
    start: AccumulationReportStart
    groups: seq[ServiceGroup]
  PreparedAccumulationOperands* = object ## Projection preparation is not a complete service invocation or accumulation certificate.
    data: nil OperandData
  OperandServiceInfo* = object ## Copied metadata exposes a protocol identity and count without mutable group storage.
    service*: ServiceIndex
    operands*: int
  ## Bound storage retains the actual admitted-block queue separately from the pure projection.
  BlockOperandData = ref object
    queue: BlockAccumulationQueue
    projection: PreparedAccumulationOperands
  BlockAccumulationOperands* = object ## Only preparation from a genuine bound queue can construct this immutable handle.
    data: nil BlockOperandData
  AccumulationOperandResult*[T] = object ## Success alone carries a complete typed handle/member under checked-build contracts.
    case status: AccumulationOperandError
    of None:
      completed: T # Successful extraction retains the requested owner or copied metadata.
    else:
      discard      # No fabricated empty success or accepted prefix after refusal.

func error*[T](outcome: AccumulationOperandResult[T]): AccumulationOperandError =
  ## Inspect a reason without permitting external retagging.
  outcome.status
func value*[T](outcome: AccumulationOperandResult[T]): T {.inline,
    requires: outcome.status == AccumulationOperandError.None.} =
  ## Extract complete selected success only; callers must inspect error first.
  outcome.completed

## Prove each sum against its ceiling before addition; integer wrapping is never a size proof.
func charge(total: var uint64, amount, maximum: uint64): bool =
  if amount > maximum-total: return false # Previous charges establish total <= maximum.
  total += amount
  true

## Numeric service order is deterministic; the explicit traversal ordinal preserves all intra-service order.
func compareDescriptor(a, b: Descriptor): int =
  if uint32(a.service) < uint32(b.service): return -1 # Lower service IDs form earlier groups.
  if uint32(a.service) > uint32(b.service): return 1 # Higher service IDs form later groups.
  if a.order < b.order: return -1 # Earlier report/digest remains first for this service.
  if a.order > b.order: return 1 # Sorting stability is not assumed.
  0

proc operandServiceCount*(plan: PreparedAccumulationOperands): AccumulationOperandResult[int] =
  ## Count groups; a missing owner is different from a successfully prepared empty prefix.
  let data = plan.data
  if data == nil: return AccumulationOperandResult[int](
      status: AccumulationOperandError.Uninitialized) # No validated groups.
  AccumulationOperandResult[int](status: AccumulationOperandError.None, completed: data.groups.len)

proc operandQueue*(plan: PreparedAccumulationOperands): AccumulationOperandResult[
    AccumulationQueuePlan] =
  ## Retain the exact priority projection independently of every caller handle.
  let data = plan.data
  if data == nil: return AccumulationOperandResult[AccumulationQueuePlan](
      status: AccumulationOperandError.Uninitialized) # No default source.
  AccumulationOperandResult[AccumulationQueuePlan](status: AccumulationOperandError.None,
      completed: data.source)

proc operandReportPrefix*(plan: PreparedAccumulationOperands): AccumulationOperandResult[
    AccumulationReportPrefix] =
  ## Report the selected count after operandReportStart; preparation does not claim that any reports executed.
  let data = plan.data
  if data == nil: return AccumulationOperandResult[AccumulationReportPrefix](
      status: AccumulationOperandError.Uninitialized) # No default prefix.
  AccumulationOperandResult[AccumulationReportPrefix](status: AccumulationOperandError.None,
      completed: data.prefix)

proc operandReportStart*(plan: PreparedAccumulationOperands): AccumulationOperandResult[
    AccumulationReportStart] =
  ## Return the retained original-queue start; ordinary prefix preparation always starts at zero.
  let data = plan.data
  if data == nil:
    return AccumulationOperandResult[AccumulationReportStart](
        status: AccumulationOperandError.Uninitialized) # No fabricated range provenance.
  AccumulationOperandResult[AccumulationReportStart](status: AccumulationOperandError.None,
      completed: data.start)

proc operandServiceAt*(plan: PreparedAccumulationOperands,
    index: OperandServiceIndex): AccumulationOperandResult[OperandServiceInfo] =
  ## Copy a group's service/count after checking its nominal ordinal before narrowing.
  let data = plan.data
  if data == nil: return AccumulationOperandResult[OperandServiceInfo](
      status: AccumulationOperandError.Uninitialized) # No storage.
  if uint64(index) >= uint64(data.groups.len):
    return AccumulationOperandResult[OperandServiceInfo](
        status: AccumulationOperandError.InvalidIndex) # Prove conversion/access.
  let group = data.groups[int(uint64(index))]
  AccumulationOperandResult[OperandServiceInfo](status: AccumulationOperandError.None,
    completed: OperandServiceInfo(service: group.service, operands: group.operands.len))

proc serviceOperandAt*(plan: PreparedAccumulationOperands, service: OperandServiceIndex,
    index: ServiceOperandIndex): AccumulationOperandResult[OwnedOperand] =
  ## Retain a complete C.2 operand after source reports, groups and prepared-plan handles leave scope.
  let data = plan.data
  if data == nil: return AccumulationOperandResult[OwnedOperand](
      status: AccumulationOperandError.Uninitialized) # No default operand.
  if uint64(service) >= uint64(data.groups.len):
    return AccumulationOperandResult[OwnedOperand](
        status: AccumulationOperandError.InvalidIndex) # Parent before child.
  let group = data.groups[int(uint64(service))]
  if uint64(index) >= uint64(group.operands.len):
    return AccumulationOperandResult[OwnedOperand](
        status: AccumulationOperandError.InvalidIndex) # Child before narrowing.
  AccumulationOperandResult[OwnedOperand](status: AccumulationOperandError.None,
    completed: group.operands[int(uint64(index))])

# Prepare one bounded original-queue range; the public prefix wrapper supplies start zero.
proc prepareOperandRange(queue: AccumulationQueuePlan, start: AccumulationReportStart,
    prefix: AccumulationReportPrefix, config: AccumulationOperandConfig): AccumulationOperandResult[
        PreparedAccumulationOperands] =
  # Refuse without publishing partially materialized groups or range provenance.
  template fail(reason: AccumulationOperandError) =
    return AccumulationOperandResult[PreparedAccumulationOperands](status: reason)
  if uint64(config.operands) > uint64(high(int) div sizeof(Descriptor)) or
      uint64(config.services) > uint64(high(int) div sizeof(ServiceGroup)) or
      uint64(config.totalBytes) > uint64(high(int)):
    fail(AccumulationOperandError.InvalidConfig) # Prove descriptor/wire extents fit native allocations.
  let count = queue.accumulationCount
  if count.error != AccumulationQueueError.None:
    fail(AccumulationOperandError.InvalidQueue) # Missing plans cannot imply an empty successful prefix.
  if uint64(start) > uint64(count.value) or uint64(prefix) > uint64(count.value) - uint64(start):
    fail(AccumulationOperandError.InvalidPrefix) # Check before native conversion or priority access.
  if uint64(prefix) > uint64(config.reports):
    fail(AccumulationOperandError.LimitExceeded) # Bound prefix traversal even before digest descriptors.
  var descriptors: seq[Descriptor] = @[]
  var blobs = 0'u64
  var wire = 0'u64
  # Walk reports then digests exactly as the accone sequence comprehension specifies.
  for i in 0..<int(uint64(prefix)):
    # The checked range proves this addition stays inside the original native queue.
    let report = queue.accumulationAt(AccumulationIndex(uint64(start) + uint64(i))).value
    let meta = ownedReportInfo(report).value
    # Every digest creates an operand, including error and empty-success work results.
    for j in 0..<meta.digestCount:
      if uint64(descriptors.len) >= uint64(config.operands):
        fail(AccumulationOperandError.LimitExceeded) # Bound descriptor growth before adding the next item.
      let digest = ownedReportDigest(report, j).value
      let output = if digest.output.kind == WorkKind.Success: digest.output.length else: 0 # Error variants have no output bytes.
      let auth = uint64(meta.authBytes)
      let payload = uint64(output)
      if auth > uint64(config.operand.authBytes) or payload > uint64(config.operand.outputBytes):
        fail(AccumulationOperandError.LimitExceeded) # Bound both independent payload sources before copying.
      var perBlobs = 0'u64
      if not charge(perBlobs, payload, uint64(config.operand.totalBlobBytes)) or
          not charge(perBlobs, auth, uint64(config.operand.totalBlobBytes)) or
          not charge(blobs, perBlobs, uint64(config.totalBlobBytes)):
        fail(AccumulationOperandError.LimitExceeded) # Include a report's shared trace once for each actual operand.
      # Exact C.2 size: outer tag, four hashes, natural gas, work tag/payload and natural trace length/data.
      var size = 129'u64+uint64(natural.encode(JamNatural(uint64(digest.accumulateGas))).len)+1 +
        uint64(natural.encode(JamNatural(auth)).len)
      if digest.output.kind == WorkKind.Success:
        size += uint64(natural.encode(JamNatural(payload)).len) # Only success carries a result length prefix.
      if size > uint64(config.operand.maxBytes) or
          not charge(size, payload, uint64(config.operand.maxBytes)) or
          not charge(size, auth, uint64(config.operand.maxBytes)) or
          not charge(wire, size, uint64(config.totalBytes)):
        fail(AccumulationOperandError.LimitExceeded) # Prove per-record and complete retained wire extents before allocation.
      descriptors.add(Descriptor(report: report, service: digest.service, digest: j,
        order: descriptors.len, wireBytes: int(size), outputBytes: output,
            authBytes: meta.authBytes))
  descriptors.sort(compareDescriptor)
  var services = 0'u64
  # Count the union of report-derived service IDs before constructing any operand owners.
  for i in 0..<descriptors.len:
    # Count each service only at the start of its sorted descriptor run.
    if i == 0 or uint32(descriptors[i].service) != uint32(descriptors[i-1].service):
      if services >= uint64(config.services):
        fail(AccumulationOperandError.LimitExceeded) # Refuse a later new group atomically.
      inc services
  var groups: seq[ServiceGroup] = @[]
  # Materialize through the established C.2 codec only after complete prefix preflight succeeded.
  for item in descriptors:
    let meta = ownedReportInfo(item.report).value
    let digest = ownedReportDigest(item.report, item.digest).value
    var trace = newSeq[byte](item.authBytes)
    let copiedTrace = copyReportBlob(item.report, 0, trace)
    if copiedTrace.error != OwnershipError.None or copiedTrace.value != trace.len:
      fail(AccumulationOperandError.InvalidOperand) # No partial copied source can produce an owner.
    var output = failedOperandOutput(WorkKind.OutOfGas)
    # Successful work owns copyable result bytes; errors retain only their original discriminator.
    if digest.output.kind == WorkKind.Success:
      var payload = newSeq[byte](item.outputBytes)
      let copied = copyReportBlob(item.report, item.digest+1, payload)
      if copied.error != OwnershipError.None or copied.value != payload.len:
        fail(AccumulationOperandError.InvalidOperand) # Preserve the exact selected report/digest association.
      output = successfulOperandOutput(payload)
    else:
      output = failedOperandOutput(digest.output.kind) # Preserve each original work-error discriminator.
    let source = AccumulationOperand(packageHash: meta.header.packageHash,
      segmentRoot: meta.header.segmentRoot, authorizer: meta.authorizer,
      payloadHash: digest.payloadHash, gas: digest.accumulateGas, output: output, authTrace: trace)
    var bytes = newSeq[byte](item.wireBytes)
    let encoded = encodeOperand(source, config.operand, bytes)
    if encoded.error != RecordError.None or encoded.value != bytes.len:
      fail(AccumulationOperandError.InvalidOperand) # The C.2 encoder remains authoritative for the complete source.
    let captured = decodeOperand(bytes, config.operand)
    if captured.error != RecordError.None or captured.value.consumed != bytes.len:
      fail(AccumulationOperandError.InvalidOperand) # No borrowed coordinates escape a complete capture.
    if groups.len == 0 or uint32(groups[^1].service) != uint32(item.service):
      groups.add(ServiceGroup(service: item.service, operands: @[])) # Start the next numerically ordered group.
    groups[^1].operands.add(captured.value.owner)
  AccumulationOperandResult[PreparedAccumulationOperands](status: AccumulationOperandError.None,
    completed: PreparedAccumulationOperands(data: OperandData(source: queue, start: start,
        prefix: prefix, groups: groups)))

proc prepareAccumulationOperands*(queue: AccumulationQueuePlan, prefix: AccumulationReportPrefix,
    config: AccumulationOperandConfig): AccumulationOperandResult[PreparedAccumulationOperands] =
  ## Prepare C.2 operands for a start-zero priority prefix; excluded/deferred rows remain unavailable.
  ## Borrow the immutable source during the call and retain it on success; all bounds precede payload copying.
  prepareOperandRange(queue, AccumulationReportStart(0), prefix, config)

proc prepareAccumulationOperandRange*(queue: AccumulationQueuePlan, start: AccumulationReportStart,
    prefix: AccumulationReportPrefix, config: AccumulationOperandConfig): AccumulationOperandResult[
        PreparedAccumulationOperands] =
  ## Prepare only the checked original-queue range, preserving report/digest order within each numeric service group.
  ## The retained start/count do not certify execution; no queue reconstruction, gas selection or state write occurs.
  prepareOperandRange(queue, start, prefix, config)

proc prepareBlockAccumulationOperands*(queue: BlockAccumulationQueue,
    prefix: AccumulationReportPrefix, config: AccumulationOperandConfig): AccumulationOperandResult[
        BlockAccumulationOperands] =
  ## Bind preparation to a genuine admitted-block queue while keeping the chosen prefix explicitly caller supplied.
  let projection = queue.accumulationProjection
  if projection.error != AccumulationQueueError.None:
    return AccumulationOperandResult[BlockAccumulationOperands](
        status: AccumulationOperandError.InvalidQueue) # No forged binding.
  let prepared = prepareAccumulationOperands(projection.value, prefix, config)
  if prepared.error != AccumulationOperandError.None:
    return AccumulationOperandResult[BlockAccumulationOperands](status: prepared.error) # No bound partial prefix.
  AccumulationOperandResult[BlockAccumulationOperands](status: AccumulationOperandError.None,
    completed: BlockAccumulationOperands(data: BlockOperandData(queue: queue,
        projection: prepared.value)))

proc operandBlockQueue*(bound: BlockAccumulationOperands): AccumulationOperandResult[
    BlockAccumulationQueue] =
  ## Retain the genuine block queue independently of the original binding handle's lifetime.
  let data = bound.data
  if data == nil: return AccumulationOperandResult[BlockAccumulationQueue](
      status: AccumulationOperandError.Uninitialized) # No default certificate.
  AccumulationOperandResult[BlockAccumulationQueue](status: AccumulationOperandError.None,
      completed: data.queue)

proc operandProjection*(bound: BlockAccumulationOperands): AccumulationOperandResult[
    PreparedAccumulationOperands] =
  ## Retain the derived report-input projection without claiming service invocation/execution.
  let data = bound.data
  if data == nil: return AccumulationOperandResult[PreparedAccumulationOperands](
      status: AccumulationOperandError.Uninitialized) # No default projection.
  AccumulationOperandResult[PreparedAccumulationOperands](status: AccumulationOperandError.None,
      completed: data.projection)
