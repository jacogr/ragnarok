# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native report-prefix/service grouping, exact C.2 mapping, limits and ownership tests.
##
## Hastur main replays 146 independently derived cases, literal service/order/error boundaries,
## a genuinely bound block queue and repeated ARC release; this file defines no production APIs.

# @@Verification={"arc": "accumulation_operands_arc_release"}

import std/assertions
import std/envvars
import std/strutils
import std/syncio
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/natural as codec_natural
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/header as codec_header
import ../../support/state_report_context
import ../../support/state_report_admission_context
import ../../support/testing_arc_evidence

## Refuse cryptographic providers after real signed inputs exist, proving preparation has no crypto side effects.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Independent finite budgets cover traversal, copied descriptors, groups and full C.2 wire.
proc cfg(): AccumulationOperandConfig =
  AccumulationOperandConfig(reports: ElementLimit(1000), operands: ElementLimit(16000),
    services: ElementLimit(16000), totalBytes: ByteLimit(10000000), totalBlobBytes: ByteLimit(
        10000000),
    operand: OperandLimits(outputBytes: ByteLimit(100000), authBytes: ByteLimit(100000),
      totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(1000000)))

## Use the admitted fixture's exact epoch/core policy, with larger projection-only queue budgets.
proc queueConfig(cores = 2'u64, slots = 12'u64): AccumulationQueueConfig =
  result = AccumulationQueueConfig(queues: config().packages.queues,
    items: ElementLimit(10000), dependencies: ElementLimit(80000))
  result.queues.cores = CoreCount(cores)
  result.queues.epochSlots = EpochSlots(slots)
  result.queues.perSlot = ElementLimit(10000)
  result.queues.totalItems = ElementLimit(10000)
  result.queues.totalDependencies = ElementLimit(80000)

## Independently copy exact fixture bytes into native owned storage.
proc fixture(): OwnedReport {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Binary data must not pass through text decoding.
  decodeOwnedReport(bytes, 2).value

## Authored source keeps custom trace/result spans attached to one stable pool during canonical capture.
proc report(base: OwnedReport, id: byte, services: openArray[uint32],
    gases: openArray[uint64], tags: openArray[WorkKind]): OwnedReport =
  var pool = reportBytes(base)
  var changed = decodeReportBorrowed(pool, 2).value
  changed.header.packageHash.bytes = default(array[32, byte])
  changed.header.packageHash.bytes[0] = id
  changed.header.segmentRoot.bytes = default(array[32, byte])
  changed.header.segmentRoot.bytes[0] = id+20
  changed.authorizer.bytes = default(array[32, byte])
  changed.authorizer.bytes[0] = id+40
  changed.authGas = Gas(high(uint64))
  changed.prerequisiteCount = 0
  changed.lookupCount = 0
  let authOffset = pool.len
  pool.add(id)
  pool.add(8'u8)
  changed.authOutput = BlobSpan(offset: authOffset, length: 2)
  let payloadOffset = pool.len
  pool.add(7'u8)
  pool.add(id)
  pool.add(9'u8)
  let first = changed.digests[0]
  changed.digestCount = services.len
  # Each independent digest carries unmistakably different gas/payload/refinement fields.
  for i in 0..<services.len:
    changed.digests[i] = first
    changed.digests[i].service = ServiceIndex(services[i])
    changed.digests[i].accumulateGas = Gas(gases[i])
    changed.digests[i].refine.gasUsed = Gas(high(uint64))
    changed.digests[i].payloadHash = PayloadHash(default(array[32, byte]))
    var payloadHash = default(array[32, byte])
    payloadHash[0] = byte(i+60)
    changed.digests[i].payloadHash = PayloadHash(payloadHash)
    if tags[i] == WorkKind.Success:
      changed.digests[i].output = successfulWork(BlobSpan(offset: payloadOffset, length: 3)) # Stable source pool.
    else:
      changed.digests[i].output = failedWork(tags[
          i]) # Preserve valid errors as values, never preparation failures.
  var output = newSeq[byte](pool.len+4096)
  let encoded = encodeReportBorrowed(changed, pool, 2, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 2).value

## Form an all-immediate projection without pretending it has complete block-admission provenance.
proc queue(reports: openArray[OwnedReport]): AccumulationQueuePlan =
  planAccumulationQueues(reports, newSeq[byte](12), newSeq[byte](12), HeaderSlot(0), queueConfig()).value

## Copy complete canonical operand bytes for independent golden/reference comparisons.
proc bytes(owner: OwnedOperand): seq[byte] =
  result = newSeq[byte](operandInfo(owner).value.consumed)
  assert encodeOwnedOperand(owner, cfg().operand, result).error == RecordError.None

## Check exact numeric service enumeration and retain repeated-service report/digest order within each group.
proc literal(base: OwnedReport): AccumulationQueuePlan =
  let a = report(base, 2, [9'u32, 42], [127'u64, 128], [WorkKind.Success, WorkKind.Panic])
  let b = report(base, 1, [0'u32, 9, high(uint32)], [high(uint64), 99, 0],
    [WorkKind.Bad, WorkKind.Success, WorkKind.Big])
  result = queue([a, b]) # Report order deliberately opposes package/core numeric order.
  let prepared = prepareAccumulationOperands(result, AccumulationReportPrefix(2), cfg()).value
  assert prepared.operandServiceCount.value == 4
  assert uint64(prepared.operandReportPrefix.value) == 2
  assert prepared.operandQueue.value.accumulationCount.value == 2
  # Fixed numeric service IDs must order groups independently of source report identity.
  for i, service in [0'u32, 9, 42, high(uint32)]:
    assert uint32(prepared.operandServiceAt(OperandServiceIndex(i)).value.service) ==
        service # Fixed service order.
  assert prepared.operandServiceAt(OperandServiceIndex(1)).value.operands == 2
  let first = prepared.serviceOperandAt(OperandServiceIndex(1), ServiceOperandIndex(0)).value
  let second = prepared.serviceOperandAt(OperandServiceIndex(1), ServiceOperandIndex(1)).value
  let info = operandInfo(first).value
  assert info.packageHash.bytes[0] == 2 and info.segmentRoot.bytes[0] == 22 and
      info.authorizer.bytes[0] == 42
  assert array[32, byte](info.payloadHash)[0] == 60 and uint64(info.gas) == 127
  assert uint64(operandInfo(second).value.gas) == 99 and operandInfo(
      second).value.packageHash.bytes[0] == 1
  var trace = newSeq[byte](2)
  var payload = newSeq[byte](3)
  assert ownedReportInfo(a).value.authBytes == trace.len
  assert copyOperandTrace(first, trace).value == 2 and trace == @[2'u8, 8]
  assert copyOperandOutput(first, payload).value == 3 and payload == @[7'u8, 2, 9]
  payload[0] = 0 # Extracted mutable copies cannot alter the retained operand.
  assert copyOperandOutput(first, payload).value == 3 and payload[0] == 7
  let failed = prepared.serviceOperandAt(OperandServiceIndex(2), ServiceOperandIndex(0)).value
  assert operandInfo(failed).value.output.kind == WorkKind.Panic
  assert copyOperandOutput(failed, payload).error == RecordError.NoPayload
  assert copyOperandTrace(failed, trace).value == 2 and trace == @[2'u8, 8]
  let prefix = prepareAccumulationOperands(result, AccumulationReportPrefix(1), cfg()).value
  assert prefix.operandServiceCount.value == 2
  assert uint32(prefix.operandServiceAt(OperandServiceIndex(0)).value.service) == 9
  # Every work error survives preparation with its exact tag and authorization trace.
  for tag in [WorkKind.OutOfGas, WorkKind.Panic, WorkKind.BadExports, WorkKind.Oversize,
      WorkKind.Bad, WorkKind.Big]:
    let source = queue([report(base, 3, [7'u32], [128'u64], [tag])])
    let group = prepareAccumulationOperands(source, AccumulationReportPrefix(1), cfg()).value
    let value = group.serviceOperandAt(OperandServiceIndex(0), ServiceOperandIndex(0)).value
    assert operandInfo(value).value.output.kind == tag
    assert copyOperandOutput(value, payload).error == RecordError.NoPayload

## Replay exact operand bytes from six published queue cases at three prefixes and 128 authored multi-service cases.
proc projections() {.raises.} =
  var total = 0
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_OPERANDS")).splitLines:
    if line.len == 0: continue # Ignore only the final transport newline.
    let f = line.splitWhitespace
    var available: seq[OwnedReport] = @[]
    let cores = uint64(parseInt(f[1]))
    if f[6] != "-":
      for raw in f[6].split(','): available.add(decodeOwnedReport(unhex(raw), cores).value) # Full original bytes.
    let source = planAccumulationQueues(available, unhex(f[4]), unhex(f[5]), HeaderSlot(parseInt(f[3])),
      queueConfig(cores, uint64(parseInt(f[2])))).value
    let outcome = prepareAccumulationOperands(source, AccumulationReportPrefix(parseInt(f[7])), cfg())
    assert outcome.error == AccumulationOperandError.None, f[0] & " " & $outcome.error
    let owner = outcome.value
    let groups = if f[8] == "-": newSeq[string](0) else: f[8].split(';') # Explicit empty prefix stays empty.
    assert owner.operandServiceCount.value == groups.len, f[0]
    # Each expected group is independently sorted by service, with untouched inner source order.
    for i in 0..<groups.len:
      let fields = groups[i].split(':')
      let info = owner.operandServiceAt(OperandServiceIndex(i)).value
      assert uint32(info.service) == uint32(parseInt(fields[0])), f[0]
      let expected = fields[1].split(',')
      assert info.operands == expected.len, f[0]
      # Exact whole-record equality checks every source-derived field and canonical framing.
      for j in 0..<expected.len:
        let operand = owner.serviceOperandAt(OperandServiceIndex(i), ServiceOperandIndex(j)).value
        assert bytes(operand) == unhex(expected[j]), f[0] & " " & $i & " " &
            $j # Whole C.2 record, including natural gas and errors.
    inc total
  assert total == 146

## Exact/one-below budgets apply to the whole prefix, including a later new group and duplicated trace bytes.
proc boundaries(source: AccumulationQueuePlan) =
  let accepted = prepareAccumulationOperands(source, AccumulationReportPrefix(2), cfg()).value
  var exact = cfg()
  exact.reports = ElementLimit(2)
  exact.operands = ElementLimit(5)
  exact.services = ElementLimit(4)
  var totalBytes = 0'u64
  var totalBlobs = 0'u64
  var largest = 0
  # Derive independent observed totals from complete owners before enforcing exact construction limits.
  for i in 0..<accepted.operandServiceCount.value:
    let group = accepted.operandServiceAt(OperandServiceIndex(i)).value
    # Include every independently retained record in aggregate byte/blob limits.
    for j in 0..<group.operands:
      let info = operandInfo(accepted.serviceOperandAt(OperandServiceIndex(i), ServiceOperandIndex(
          j)).value).value
      totalBytes += uint64(info.consumed)
      totalBlobs += uint64(info.authBytes)
      if info.output.kind == WorkKind.Success: totalBlobs += uint64(
          info.output.length) # Errors carry no result blob.
      largest = max(largest, info.consumed)
  exact.totalBytes = ByteLimit(totalBytes)
  exact.totalBlobBytes = ByteLimit(totalBlobs)
  exact.operand = OperandLimits(outputBytes: ByteLimit(3), authBytes: ByteLimit(2),
    totalBlobBytes: ByteLimit(5), maxBytes: ByteLimit(largest))
  assert prepareAccumulationOperands(source, AccumulationReportPrefix(2), exact).error ==
      AccumulationOperandError.None
  # Refuse each independent late boundary without publishing any partial earlier service.
  for field in 0..<9:
    var limited = exact
    case field
    of 0: limited.reports = ElementLimit(1) # Prefix traversal.
    of 1: limited.operands = ElementLimit(4) # Final digest descriptor.
    of 2: limited.services = ElementLimit(3) # Final numeric service group.
    of 3: limited.totalBytes = ByteLimit(totalBytes-1) # Final retained byte.
    of 4: limited.totalBlobBytes = ByteLimit(totalBlobs-1) # Shared trace charged per operand.
    of 5: limited.operand.outputBytes = ByteLimit(2) # Successful result payload.
    of 6: limited.operand.authBytes = ByteLimit(1) # Authorization trace on success and error.
    of 7: limited.operand.totalBlobBytes = ByteLimit(4) # Combined output plus trace.
    else: limited.operand.maxBytes = ByteLimit(largest-1) # Complete C.2 wire.
    assert prepareAccumulationOperands(source, AccumulationReportPrefix(2), limited).error ==
        AccumulationOperandError.LimitExceeded, $field
  assert prepareAccumulationOperands(source, AccumulationReportPrefix(high(uint64)), exact).error ==
      AccumulationOperandError.InvalidPrefix
  assert prepareAccumulationOperands(default(AccumulationQueuePlan), AccumulationReportPrefix(0),
      exact).error == AccumulationOperandError.InvalidQueue
  assert prepareAccumulationOperands(source, AccumulationReportPrefix(0), default(
      AccumulationOperandConfig)).value.operandServiceCount.value == 0
  var oversized = exact
  oversized.operands = ElementLimit(high(uint64))
  assert prepareAccumulationOperands(source, AccumulationReportPrefix(0), oversized).error ==
      AccumulationOperandError.InvalidConfig
  assert default(PreparedAccumulationOperands).operandServiceCount.error ==
      AccumulationOperandError.Uninitialized
  assert default(PreparedAccumulationOperands).operandQueue.error ==
      AccumulationOperandError.Uninitialized
  assert default(PreparedAccumulationOperands).operandReportPrefix.error ==
      AccumulationOperandError.Uninitialized
  assert default(PreparedAccumulationOperands).operandServiceAt(OperandServiceIndex(0)).error ==
      AccumulationOperandError.Uninitialized
  assert default(PreparedAccumulationOperands).serviceOperandAt(OperandServiceIndex(0),
      ServiceOperandIndex(0)).error == AccumulationOperandError.Uninitialized
  assert default(BlockAccumulationOperands).operandBlockQueue.error ==
      AccumulationOperandError.Uninitialized
  assert default(BlockAccumulationOperands).operandProjection.error ==
      AccumulationOperandError.Uninitialized
  assert accepted.operandServiceAt(OperandServiceIndex(high(uint64))).error ==
      AccumulationOperandError.InvalidIndex
  assert accepted.serviceOperandAt(OperandServiceIndex(high(uint64)), ServiceOperandIndex(
      0)).error == AccumulationOperandError.InvalidIndex
  assert accepted.serviceOperandAt(OperandServiceIndex(1), ServiceOperandIndex(high(
      uint64))).error == AccumulationOperandError.InvalidIndex
  assert prepareBlockAccumulationOperands(default(BlockAccumulationQueue), AccumulationReportPrefix(
      0), exact).error == AccumulationOperandError.InvalidQueue

## Genuine signed admission and availability feed the bound adapter; retained children survive source scope exit.
proc boundCase(base: OwnedReport): OwnedOperand =
  var signedOptions0 = signedBlockFixtureConfig()
  signedOptions0.withAvailable = true
  let context = authored(base, signedOptions0)
  let admission = planBlockReports(context.staged, context.older, config()).value
  let bound = planBlockAccumulationQueue(admission, queueConfig()).value
  let root = context.original.snapshot.value.commitment.root
  failHash(1)
  let outcome = prepareBlockAccumulationOperands(bound, AccumulationReportPrefix(1), cfg())
  failHash(0)
  assert outcome.error == AccumulationOperandError.None
  let view = outcome.value.operandProjection.value
  assert view.operandServiceCount.value == 1
  assert outcome.value.operandBlockQueue.value.accumulationAdmission.error ==
      AccumulationQueueError.None
  assert array[32, byte](context.original.snapshot.value.commitment.root) == array[32, byte](root)
  assert prepareBlockAccumulationOperands(bound, AccumulationReportPrefix(2), cfg()).error ==
      AccumulationOperandError.InvalidPrefix
  result = view.serviceOperandAt(OperandServiceIndex(0), ServiceOperandIndex(0)).value

## Repeated materialization/refusal must release scratch, source references, groups and operand wire fully.
proc lifetime(source: AccumulationQueuePlan) =
  discard prepareAccumulationOperands(source, AccumulationReportPrefix(2), cfg()) # Warm deterministic runtime allocations.
  let before = getOccupiedMem()
  # Each cycle includes complete owner creation and a late service-bound refusal.
  for i in 0..<1000:
    let accepted = prepareAccumulationOperands(source, AccumulationReportPrefix(2), cfg())
    assert accepted.error == AccumulationOperandError.None
    var limited = cfg()
    limited.services = ElementLimit(3)
    assert prepareAccumulationOperands(source, AccumulationReportPrefix(2), limited).error ==
        AccumulationOperandError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_operands", 1000, before, after)

## Native assertions own every application verdict; unexpected fixture errors cannot produce success.
proc main() {.raises.} =
  let base = fixture()
  let source = literal(base)
  projections()
  boundaries(source)
  let child = boundCase(base)
  assert operandInfo(child).error == RecordError.None # All bound parent/context locals have left scope.
  lifetime(source)
  echo "PASS accumulation operands: 146 projections, service/prefix order, C.2 bytes, limits and retained owners"
try:
  main() # Execute every native phase through the supported Hastur runner.
except:
  quit(2) # Missing fixture transport or unexpected exceptions remain failing tests.
