# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native prepared-input to fetch integration with independent literal C.2 records and ARC evidence.
## Covers service selection, ordering, fresh limits, empty lists and retained context ownership.

# @@Verification={"arc": "pvm_fetch_invocation_arc_release"}

import std/[assertions, syncio]
import ../../../src/state/[accumulation_fetch, accumulation_inputs, accumulation_operands,
  accumulation_queue]
import ../../../src/codec/[bounded, composite, natural, work_digest, work_report, report_owned,
  c2_records, state_workqueues, state_privileges, header]
import ../../../src/pvm/[host_fetch, machine, step]
import ../../support/arc_evidence

## Independent local caps cover the complete selected service, not all groups in the source plan.
proc limits(): FetchAccumulationLimits =
  FetchAccumulationLimits(items: ElementLimit(10), bytes: ByteLimit(4096),
    operand: OperandLimits(outputBytes: ByteLimit(100), authBytes: ByteLimit(100),
      totalBlobBytes: ByteLimit(200), maxBytes: ByteLimit(1000)))

## Authored report fields make operand copying observable without an external test fixture.
proc plan(): PreparedAccumulationInputs =
  var report = default(WorkReport)
  report.header.erasureShards = ErasureShards(6)
  report.header.packageHash.bytes[0] = 11
  report.header.segmentRoot.bytes[0] = 12
  report.authorizer.bytes[0] = 13
  report.authOutput = BlobSpan(offset: 3, length: 2)
  report.digestCount = 4
  for i in 0..<4:
    # One foreign service separates selection from the source report's digest order.
    report.digests[i].service = ServiceIndex(if i == 1: 7 else: 42)
    report.digests[i].accumulateGas = Gas(128)
    var hash = default(array[32, byte])
    hash[0] = byte(14+i)
    report.digests[i].payloadHash = PayloadHash(hash)
    if i == 2:
      report.digests[i].output = failedWork(WorkKind.Panic) # Errors remain input records.
    else:
      report.digests[i].output = successfulWork(BlobSpan(offset: 0,
        length: (if i == 3: 0 else: 3))) # Empty success remains distinct from a work error.
  var wire = newSeq[byte](4096)
  let encoded = encodeReportBorrowed(report, [1'u8, 2, 3, 4, 5], 2, wire)
  assert encoded.error == CompositeError.None
  let owned = decodeOwnedReport(wire.toOpenArray(0, encoded.written-1), 2).value
  let config = AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2),
    epochSlots: EpochSlots(12), perSlot: ElementLimit(10), totalItems: ElementLimit(10),
    perDependencies: ElementLimit(10), totalDependencies: ElementLimit(10),
    reportBytes: ByteLimit(4096), maxBytes: ByteLimit(10000)),
    items: ElementLimit(10), dependencies: ElementLimit(10))
  let queue = planAccumulationQueues([owned], newSeq[byte](12), newSeq[byte](12),
    HeaderSlot(0), config).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(1),
    AccumulationOperandConfig(reports: ElementLimit(1), operands: ElementLimit(4),
      services: ElementLimit(2), totalBytes: ByteLimit(4096), totalBlobBytes: ByteLimit(100),
      operand: limits().operand)).value
  var transfers = @[
    DeferredTransfer(source: ServiceIndex(9), destination: ServiceIndex(42), gas: Gas(128)),
    DeferredTransfer(source: ServiceIndex(8), destination: ServiceIndex(7)),
    DeferredTransfer(source: ServiceIndex(3), destination: ServiceIndex(42), gas: Gas(128))]
  result = prepareAccumulationInputs(operands, transfers,
    [AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(0))],
    AccumulationInputConfig(inputs: ElementLimit(7), services: ElementLimit(3),
      allowances: ElementLimit(1))).value
  transfers[0].source = ServiceIndex(123) # Mutation cannot affect the retained plan or later fetch.

## Trace bytes witness preservation of unrelated context attachments.
proc base(): FetchContext =
  captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
    FetchPresence.Present, [73'u8], FetchTraceLimit(1)).value

## Literal records for service 42 establish wire identity without invoking the production C.2 encoder.
proc record(i: int): seq[byte] =
  if i < 2:
    # Complete fixed transfer: discriminator, IDs and final fixed-width gas.
    result = newSeq[byte](154)
    result[0] = 1
    result[1] = (if i == 0: 9'u8 else: 3'u8)
    result[5] = 42
    result[146] = 128 # The preceding supervisor-credit flag is explicit zero.
  else:
    # Compact gas 128 occupies two bytes; success/error variants have distinct framing.
    result = newSeq[byte](if i == 2: 139 elif i == 3: 135 else: 136)
    result[1] = 11
    result[33] = 12
    result[65] = 13
    result[97] = (if i == 2: 14'u8 elif i == 3: 16'u8 else: 17'u8)
    result[129] = 128
    result[130] = 128
    if i == 2:
      result[132] = 3 # Successful output length followed by three independently authored bytes.
      result[133] = 1
      result[134] = 2
      result[135] = 3
    elif i == 3:
      result[131] = 2 # Panic result carries only its tag, without a blob length.
    else:
      discard # Default zero success tag and length encode the empty successful output.
    result[result.len-3] = 2
    result[result.len-2] = 4
    result[result.len-1] = 5

## Fetch exact bytes through the real response implementation, checking returned full lengths too.
proc fetched(context: FetchContext, selector, index: uint64, expected: seq[byte]) =
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
    PageLimit(1)).value
  var registers = default(RegisterFile)
  registers[9] = RegisterValue(1024)
  registers[10] = RegisterValue(selector)
  registers[11] = RegisterValue(index)
  let response = fetchContextResponse(context, MachineGas(10000), registers, memory,
    MemoryByteLimit(1024)).value
  assert response.action == HostAction.Continue
  assert uint64(response.registers[7]) == uint64(expected.len)
  assert readBytes(response.memory, MemoryAddress(0), MemoryLength(expected.len),
    MemoryByteLimit(1024)).value == expected

## Captures survive destruction of the entire report/queue/input preparation graph.
proc capture(): FetchContext =
  withInvocationFetch(base(), plan(), InvocationServiceIndex(1), limits()).value

let inputs = plan()
let context = capture()
var whole = @[5'u8]
for i in 0..<5:
  # Service 42 receives its two transfers followed by the filtered report order.
  let expected = record(i)
  fetched(context, 15, uint64(i), expected)
  for octet in expected:
    whole.add(octet) # The list has one count prefix and no per-record length wrappers.
fetched(context, 14, high(uint64), whole)
fetched(context, 2, 0, @[73'u8])
let empty = withInvocationFetch(context, inputs, InvocationServiceIndex(2), limits()).value
fetched(empty, 14, 0, @[0'u8])
fetched(context, 14, 0, whole) # Replacing a child handle cannot mutate the original capture.
let foreign = withInvocationFetch(base(), inputs, InvocationServiceIndex(0), limits()).value
var foreignTransfer = newSeq[byte](154)
foreignTransfer[0] = 1
foreignTransfer[1] = 8
foreignTransfer[5] = 7
fetched(foreign, 15, 0, foreignTransfer)
assert withInvocationFetch(default(FetchContext), inputs, InvocationServiceIndex(1),
  limits()).error == InvocationFetchError.InvalidContext
assert withInvocationFetch(base(), default(PreparedAccumulationInputs), InvocationServiceIndex(0),
  limits()).error == InvocationFetchError.InvalidInputs
for index in [3'u64, 42'u64, high(uint64)]:
  # Protocol service IDs must not be silently treated as valid group ordinals.
  assert withInvocationFetch(base(), inputs, InvocationServiceIndex(index),
    limits()).error == InvocationFetchError.InvalidIndex
var exact = limits()
exact.items = ElementLimit(5)
exact.bytes = ByteLimit(whole.len)
assert withInvocationFetch(base(), inputs, InvocationServiceIndex(1), exact).error ==
    InvocationFetchError.None
for field in 0..<6:
  # Each fresh policy applies before copying, even though the earlier preparation allowed the record.
  var tight = exact
  case field
  of 0: tight.items = ElementLimit(4) # Complete selected group count.
  of 1: tight.bytes = ByteLimit(whole.len-1) # Includes the compact list prefix.
  of 2: tight.operand.outputBytes = ByteLimit(2) # Three-byte successful output.
  of 3: tight.operand.authBytes = ByteLimit(1) # Two-byte authorization trace.
  of 4: tight.operand.totalBlobBytes = ByteLimit(4) # Combined output and trace.
  else: tight.operand.maxBytes = ByteLimit(153) # Fixed transfer must also fit record policy.
  assert withInvocationFetch(base(), inputs, InvocationServiceIndex(1), tight).error ==
    InvocationFetchError.LimitExceeded
exact.items = ElementLimit(0)
exact.bytes = ByteLimit(1)
assert withInvocationFetch(base(), inputs, InvocationServiceIndex(2), exact).error ==
    InvocationFetchError.None
exact.bytes = ByteLimit(0)
assert withInvocationFetch(base(), inputs, InvocationServiceIndex(2), exact).error ==
    InvocationFetchError.LimitExceeded
assert ownedOperandSize(default(OwnedOperand), limits().operand).error == RecordError.InvalidOwner

# Owned operand sizing shares fresh-policy checks with the encoder, including the exact wire cap.
let operand = inputs.invocationInputAt(InvocationServiceIndex(1), InvocationInputIndex(
    2)).value.operand
var policy = limits().operand
policy.maxBytes = ByteLimit(139)
assert ownedOperandSize(operand, policy).value == 139
policy.maxBytes = ByteLimit(138)
assert ownedOperandSize(operand, policy).error == RecordError.LimitExceeded
var generous = limits()
generous.items = ElementLimit(high(uint64))
generous.bytes = ByteLimit(high(uint64))
assert withInvocationFetch(base(), inputs, InvocationServiceIndex(1), generous).error ==
    InvocationFetchError.None
fetched(context, 14, 0, whole) # Refused replacements leave previously retained context bytes untouched.

## Repeated conversion and capture release all temporary payloads and final list owners.
proc cycle() =
  let captured = capture()
  fetched(captured, 15, 4, record(4))
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Every intermediate preparation owner is released within each iteration.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_invocation", 1000, before, after)
echo "PVM invocation fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
