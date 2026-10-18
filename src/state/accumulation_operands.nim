# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accumulation.tex operandtuple/accone: report-derived per-service operand preparation.
##
## Exposes explicit report prefixes, bounded preparation, immutable service-group/operand access
## and a block-bound adapter retaining the queue certificate. Execution/gas allocation are separate.

import std/algorithm
import ../codec/[bounded, natural, composite, work_digest, report_owned, owned, c2_records]
import ./accumulation_queue

type
  ## A caller-selected prefix is not an executed-report count or a byte/digest ordinal.
  AccumulationReportPrefix* = distinct uint64
  ## A service-group ordinal is not the protocol service identifier stored at that position.
  OperandServiceIndex* = distinct uint64
  ## A per-service operand ordinal cannot address a service group or report queue.
  ServiceOperandIndex* = distinct uint64
  ## Independent local ceilings bound traversal, descriptors, copied payloads and retained operand wire.
  AccumulationOperandConfig* = object
    reports*, operands*, services*: ElementLimit
    totalBlobBytes*, totalBytes*: ByteLimit
    operand*: OperandLimits
  ## Default/refused alternatives expose no partial service group, input sequence or copied progress.
  AccumulationOperandError* {.pure.} = enum
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
    groups: seq[ServiceGroup]
  ## Projection preparation is not a complete service invocation or accumulation certificate.
  PreparedAccumulationOperands* = object
    data: nil OperandData
  ## Copied metadata exposes a protocol identity and count without mutable group storage.
  OperandServiceInfo* = object
    service*: ServiceIndex
    operands*: int
  ## Bound storage retains the actual admitted-block queue separately from the pure projection.
  BlockOperandData = ref object
    queue: BlockAccumulationQueue
    projection: PreparedAccumulationOperands
  ## Only preparation from a genuine bound queue can construct this immutable handle.
  BlockAccumulationOperands* = object
    data: nil BlockOperandData
  ## Success alone carries a complete typed handle/member under checked-build contracts.
  AccumulationOperandResult*[T] = object
    case status: AccumulationOperandError
    of None:
      completed: T # Successful extraction retains the requested owner or copied metadata.
    else:
      discard      # No fabricated empty success or accepted prefix after refusal.

## Inspect a reason without permitting external retagging.
func error*[T](outcome: AccumulationOperandResult[T]): AccumulationOperandError = outcome.status
## Extract complete selected success only; callers must inspect error first.
func value*[T](outcome: AccumulationOperandResult[T]): T {.inline,
    requires: outcome.status == AccumulationOperandError.None.} = outcome.completed

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

## Count groups; a missing owner is different from a successfully prepared empty prefix.
proc operandServiceCount*(plan: PreparedAccumulationOperands): AccumulationOperandResult[int] =
  let data = plan.data
  if data == nil: return AccumulationOperandResult[int](
      status: AccumulationOperandError.Uninitialized) # No validated groups.
  AccumulationOperandResult[int](status: AccumulationOperandError.None, completed: data.groups.len)

## Retain the exact priority projection independently of every caller handle.
proc operandQueue*(plan: PreparedAccumulationOperands): AccumulationOperandResult[
    AccumulationQueuePlan] =
  let data = plan.data
  if data == nil: return AccumulationOperandResult[AccumulationQueuePlan](
      status: AccumulationOperandError.Uninitialized) # No default source.
  AccumulationOperandResult[AccumulationQueuePlan](status: AccumulationOperandError.None,
      completed: data.source)

## Report the selected prefix; preparation does not claim that any reports executed.
proc operandReportPrefix*(plan: PreparedAccumulationOperands): AccumulationOperandResult[
    AccumulationReportPrefix] =
  let data = plan.data
  if data == nil: return AccumulationOperandResult[AccumulationReportPrefix](
      status: AccumulationOperandError.Uninitialized) # No default prefix.
  AccumulationOperandResult[AccumulationReportPrefix](status: AccumulationOperandError.None,
      completed: data.prefix)

## Copy a group's service/count after checking its nominal ordinal before narrowing.
proc operandServiceAt*(plan: PreparedAccumulationOperands,
    index: OperandServiceIndex): AccumulationOperandResult[OperandServiceInfo] =
  let data = plan.data
  if data == nil: return AccumulationOperandResult[OperandServiceInfo](
      status: AccumulationOperandError.Uninitialized) # No storage.
  if uint64(index) >= uint64(data.groups.len):
    return AccumulationOperandResult[OperandServiceInfo](
        status: AccumulationOperandError.InvalidIndex) # Prove conversion/access.
  let group = data.groups[int(uint64(index))]
  AccumulationOperandResult[OperandServiceInfo](status: AccumulationOperandError.None,
    completed: OperandServiceInfo(service: group.service, operands: group.operands.len))

## Retain a complete C.2 operand after source reports, groups and prepared-plan handles leave scope.
proc serviceOperandAt*(plan: PreparedAccumulationOperands, service: OperandServiceIndex,
    index: ServiceOperandIndex): AccumulationOperandResult[OwnedOperand] =
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

## Prepare i^U only for an explicit prefix of Q's priority sequence; unavailable/deferred queue rows stay excluded.
## Borrow the immutable plan during the call and retain it on success. Preflight every bound before copying blobs.
## This neither chooses a gas-dependent prefix nor adds transfer/free-allowance-only services or writes state.
proc prepareAccumulationOperands*(queue: AccumulationQueuePlan, prefix: AccumulationReportPrefix,
    config: AccumulationOperandConfig): AccumulationOperandResult[PreparedAccumulationOperands] =
  ## Refuse the entire projection without publishing partially materialized groups.
  template fail(reason: AccumulationOperandError) =
    return AccumulationOperandResult[PreparedAccumulationOperands](status: reason)
  if uint64(config.operands) > uint64(high(int) div sizeof(Descriptor)) or
      uint64(config.services) > uint64(high(int) div sizeof(ServiceGroup)) or
      uint64(config.totalBytes) > uint64(high(int)):
    fail(AccumulationOperandError.InvalidConfig) # Prove descriptor/wire extents fit native allocations.
  let count = queue.accumulationCount
  if count.error != AccumulationQueueError.None:
    fail(AccumulationOperandError.InvalidQueue) # Missing plans cannot imply an empty successful prefix.
  if uint64(prefix) > uint64(count.value):
    fail(AccumulationOperandError.InvalidPrefix) # Check before native conversion or priority access.
  if uint64(prefix) > uint64(config.reports):
    fail(AccumulationOperandError.LimitExceeded) # Bound prefix traversal even before digest descriptors.
  var descriptors: seq[Descriptor] = @[]
  var blobs = 0'u64
  var wire = 0'u64
  # Walk reports then digests exactly as the accone sequence comprehension specifies.
  for i in 0..<int(uint64(prefix)):
    let report = queue.accumulationAt(AccumulationIndex(i)).value
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
    completed: PreparedAccumulationOperands(data: OperandData(source: queue, prefix: prefix,
        groups: groups)))

## Bind preparation to a genuine admitted-block queue while keeping the chosen prefix explicitly caller supplied.
proc prepareBlockAccumulationOperands*(queue: BlockAccumulationQueue,
    prefix: AccumulationReportPrefix, config: AccumulationOperandConfig): AccumulationOperandResult[
        BlockAccumulationOperands] =
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

## Retain the genuine block queue independently of the original binding handle's lifetime.
proc operandBlockQueue*(bound: BlockAccumulationOperands): AccumulationOperandResult[
    BlockAccumulationQueue] =
  let data = bound.data
  if data == nil: return AccumulationOperandResult[BlockAccumulationQueue](
      status: AccumulationOperandError.Uninitialized) # No default certificate.
  AccumulationOperandResult[BlockAccumulationQueue](status: AccumulationOperandError.None,
      completed: data.queue)

## Retain the derived report-input projection without claiming service invocation/execution.
proc operandProjection*(bound: BlockAccumulationOperands): AccumulationOperandResult[
    PreparedAccumulationOperands] =
  let data = bound.data
  if data == nil: return AccumulationOperandResult[PreparedAccumulationOperands](
      status: AccumulationOperandError.Uninitialized) # No default projection.
  AccumulationOperandResult[PreparedAccumulationOperands](status: AccumulationOperandError.None,
      completed: data.projection)
