# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored test-only accumulation bootstrap from a real code preimage, account and allowance.
## Exposes pvmBootstrap, configured parameters and a compact JAM envelope without replacing verdicts.

import std/assertions
import ../../src/chain/parameters
import ../../src/state/[accumulation_invocation, accumulation_service, accumulation_inputs,
  accumulation_operands, accumulation_queue, accumulation_context, store]
import ../../src/codec/[bounded, composite, header, state_safrole, state_privileges,
  state_workqueues, state_accounts, state_service_values, state_trie, work_report, report_owned,
  work_digest, c2_records, assurances, state_authorization, state_layout]
import ../../src/crypto/primitives

proc pvmEnvelope*(raw: openArray[byte] = [0'u8, 0, 7, 0, 0, 0, 0, 0, 50, 0, 63], writable: seq[
    byte] = @[81'u8]): seq[byte] =
  ## Build a small envelope with one RO byte, a bounded RW payload, extra heap page and one-byte stack request.
  ## The default raw program has five traps followed by jump_ind r0 at the accumulation entry.
  ## writable supplies up to 4096 authored data bytes; the default preserves the original one-byte fixture.
  assert writable.len <= 4096 # Small authored payloads retain the original two-page RW fixture layout.
  result = @[1'u8, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 73]
  for i in 0..<3:
    result[3+i] = byte((writable.len shr (8*i)) and 255) # Validated E3 extent preserves the two-page RW layout.
  for octet in writable:
    result.add(octet) # Capture custom fixed host inputs without replacing real memory stores or reads.
  for i in 0..<4:
    result.add(byte((uint64(raw.len) shr (8*i)) and 255)) # Independent fixed E4 program extent.
  for octet in raw:
    result.add(octet) # Raw program bytes include their own framing and opcode mask.

proc pvmContextConfig*(): AccumulationContextConfig =
  ## Coherent tiny-profile chapter and aggregate ceilings for the accumulation dispatcher.
  AccumulationContextConfig(validators: ValidatorCount(6),
    queues: AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
      maxBytes: ByteLimit(5120)),
    staging: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(2017)),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(0),
      maxBytes: ByteLimit(100)), totalBytes: ByteLimit(10000))

proc pvmBootstrap*(code: openArray[byte], gas = 100'u64,
    operandCount = 0, serviceId = 42'u32,
    entropy: StateEntropyWord = default(StateEntropyWord),
    precedingService = false, includeContexts = false, extra: seq[StateEntry] = @[],
        account = default(ServiceMetadata), spareEntries = 0,
            manager = 0'u32, assigner = 0'u32): PreparedAccumulationInvocation =
  ## The allowance supplies exact gas; optional authored failed-work operands supply a nonzero input count.
  ## Returned bootstrap retains real immutable account/code/input owners after all local sources die.
  ## manager/assigner supply copied initial authority; neither changes the selected service.
  ## account supplies copied metadata; the code hash is derived from code. spareEntries (0..64) bounds extra map capacity.
  ## manager sets the initial C(12) authority independently of the selected invocation allowance.
  assert operandCount >= 0 and operandCount <= 16
  var reports: seq[OwnedReport] = @[]
  if operandCount > 0:
    # Authored zero-gas failed-work operands affect the argument count without changing declared gas.
    var report = default(WorkReport)
    report.header.erasureShards = ErasureShards(6)
    report.digestCount = operandCount
    for i in 0..<operandCount:
      report.digests[i].service = ServiceIndex(serviceId) # All operands belong to the one selected service.
      report.digests[i].output = failedWork(WorkKind.Panic)
      var payloadHash = default(array[32, byte])
      payloadHash[0] = byte(i+1)
      report.digests[i].payloadHash = PayloadHash(payloadHash) # Distinguish input order in fetch witnesses.
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
  var allowances: seq[AlwaysAccumulate] = @[]
  if precedingService:
    # A lower-ID allowance-only group catches consumers that accidentally choose ordinal zero.
    assert serviceId > 0
    allowances.add(AlwaysAccumulate(service: ServiceIndex(0)))
  allowances.add(AlwaysAccumulate(service: ServiceIndex(serviceId), gas: PrivilegeGas(gas)))
  let inputs = prepareAccumulationInputs(operands, [], allowances,
    AccumulationInputConfig(inputs: ElementLimit(16), allowances: ElementLimit(2),
      services: ElementLimit(2))).value
  var preimage = @[0'u8]
  for octet in code:
    preimage.add(octet) # Zero-length service metadata precedes the entire JAM code envelope.
  let hash = array[32, byte](blake2b256(preimage).value)
  var metadata = account
  metadata.codeHash = CodeHash(hash)
  var entries = @[serviceMetadataEntry(ServiceIndex(serviceId), metadata,
    ByteLimit(89)).value,
    servicePreimageEntry(ServiceIndex(serviceId), ServicePreimageHash(hash), preimage,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(preimage.len))).value]
  if includeContexts:
    # Actual canonical chapters authorize initial I; missing state must never be silently substituted.
    let config = pvmContextConfig()
    entries.add(authorizationEntry(AuthorizationKind.Queues,
      @[newSeq[AuthorizerHash](80), newSeq[AuthorizerHash](80)], config.queues).value)
    entries.add(validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](6),
        config.staging).value)
    entries.add(privilegeStateEntry(PrivilegeState(manager: ServiceIndex(manager), assigners: @[
        ServiceIndex(assigner), ServiceIndex(assigner)]),
      config.privileges).value)
  assert spareEntries >= 0 and spareEntries <= 64
  assert extra.len <= 64 # Keep all test-only extent additions below native and trie policy ceilings.
  for entry in extra:
    entries.add(entry) # Capture requests/other targets into the same complete map before preparing the bootstrap.
  let state = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(
      5+extra.len+spareEntries),
    perValue: ByteLimit(10000), totalValueBytes: ByteLimit(20000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(20000))).value.snapshot.value
  let service = prepareAccumulationService(inputs, InvocationServiceIndex(
      if precedingService: 1 else: 0), state, HeaderSlot(128),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(code.len),
      preimageBytes: ByteLimit(preimage.len))).value
  prepareAccumulationInvocation(service, entropy, ServiceProbeLimit(1)).value

proc pvmParameters*(): Parameters =
  ## Maximal fixed-width fields form a valid immutable parameter fixture with equal epoch/tail bounds.
  var wire = default(array[122, byte])
  for i in 0..<wire.len:
    wire[i] = 255 # Independent literal octets are reused by fetch tests and refusal probes.
  decodeParameters(wire).value
