# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored test-only accumulation bootstrap from a real code preimage, account and allowance.
## Exposes pvmBootstrap and a compact JAM envelope fixture without replacing production verdicts.

import std/assertions
import ../../src/state/[accumulation_invocation, accumulation_service, accumulation_inputs,
  accumulation_operands, accumulation_queue, store]
import ../../src/codec/[bounded, composite, header, state_safrole, state_privileges,
  state_workqueues, state_accounts, state_service_values, state_trie, work_report, report_owned,
  work_digest, c2_records]
import ../../src/crypto/primitives

## Build a small envelope with one RO byte, one RW byte, extra heap page and one-byte stack request.
## The default raw program has five traps followed by jump_ind r0 at the accumulation entry.
proc pvmEnvelope*(raw: openArray[byte] = [0'u8, 0, 7, 0, 0, 0, 0, 0, 50, 0, 63]): seq[byte] =
  result = @[1'u8, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 73, 81]
  for i in 0..<4:
    result.add(byte((uint64(raw.len) shr (8*i)) and 255)) # Independent fixed E4 program extent.
  for octet in raw:
    result.add(octet) # Raw program bytes include their own framing and opcode mask.

## The allowance supplies exact gas; optional authored failed-work operands supply a nonzero input count.
## Returned bootstrap retains real immutable account/code/input owners after all local sources die.
proc pvmBootstrap*(code: openArray[byte], gas = 100'u64,
    operandCount = 0): PreparedAccumulationInvocation =
  assert operandCount >= 0 and operandCount <= 16
  var reports: seq[OwnedReport] = @[]
  if operandCount > 0:
    # Authored zero-gas failed-work operands affect the argument count without changing declared gas.
    var report = default(WorkReport)
    report.header.erasureShards = ErasureShards(6)
    report.digestCount = operandCount
    for i in 0..<operandCount:
      report.digests[i].service = ServiceIndex(42) # All operands belong to the one selected service.
      report.digests[i].output = failedWork(WorkKind.Panic)
    var encoded = newSeq[byte](10000)
    let written = encodeReportBorrowed(report, [], 2, encoded)
    assert written.error == CompositeError.None
    reports.add(decodeOwnedReport(encoded.toOpenArray(0, written.written-1), 2).value)
  let queue = planAccumulationQueues(reports, [0'u8], [0'u8], HeaderSlot(0),
    AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(1),
      perSlot: ElementLimit(1), totalItems: ElementLimit(1), reportBytes: ByteLimit(10000),
      maxBytes: ByteLimit(20000)), items: ElementLimit(1))).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(reports.len),
    AccumulationOperandConfig(reports: ElementLimit(1), operands: ElementLimit(16),
      services: ElementLimit(1), totalBytes: ByteLimit(10000),
      operand: OperandLimits(maxBytes: ByteLimit(1000)))).value
  let inputs = prepareAccumulationInputs(operands, [],
    [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(gas))],
    AccumulationInputConfig(inputs: ElementLimit(16), allowances: ElementLimit(1),
        services: ElementLimit(1))).value
  var preimage = @[0'u8]
  for octet in code:
    preimage.add(octet) # Zero-length service metadata precedes the entire JAM code envelope.
  let hash = array[32, byte](blake2b256(preimage).value)
  let entries = [serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(codeHash: CodeHash(hash)),
    ByteLimit(89)).value,
    servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), preimage,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(preimage.len))).value]
  let state = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2),
    perValue: ByteLimit(10000), totalValueBytes: ByteLimit(20000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(20000))).value.snapshot.value
  let service = prepareAccumulationService(inputs, InvocationServiceIndex(0), state, HeaderSlot(128),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(code.len),
      preimageBytes: ByteLimit(preimage.len))).value
  prepareAccumulationInvocation(service, default(StateEntropyWord), ServiceProbeLimit(1)).value
