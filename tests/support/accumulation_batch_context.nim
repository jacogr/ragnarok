# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored common-source two-service executions with separate incoming credits and real PVM terminals.
## Complete source maps retain code, storage, requests and unrelated chapters; no production verdict is replaced.

import std/assertions
import ../../src/state/[accumulation_inputs, accumulation_operands, accumulation_queue,
  accumulation_service, accumulation_invocation, accumulation_machine, accumulation_dispatch,
  accumulation_batch, store]
import ../../src/codec/[bounded, composite, header, work_digest, c2_records, state_privileges,
  state_workqueues, state_accounts, state_service_values, state_authorization, state_safrole,
  state_layout, state_trie]
import ../../src/pvm/[initialize, machine, program, step, host_fetch, gas]
import ../../src/crypto/primitives
import ../../src/chain/parameters
import ./[pvm_accumulation_context, pvm_accumulation_program, pvm_accumulation_provision,
  accumulation_provision_integration]

type
  BatchEnding* {.pure.} = enum ## Literal final instructions distinguish normal halt from exceptional rollback.
    Halt,                  ## Normal termination retains both regular provision contributions.
    Panic,                 ## A trap discards the later regular provision and retains the first checkpoint.
    Ambiguous,             ## A readable 32-byte return exercises the nonempty-provisions gate.
    StorageHalt,           ## The sibling PVM API retains a regular storage write at halt.
    StoragePanic,          ## Panic discards a storage write made after the original checkpoint.
    StorageCheckpointPanic ## A second checkpoint retains the storage write before panic.
  BatchFixture* = object ## Mutable test-only fixture values are independently captured by the production preparation APIs.
    inputs*: PreparedAccumulationInputs ## Shared immutable service-input owner for execution provenance.
    state*: StateStore        ## Complete prior map captured independently of the fixture rows.
    entries*: seq[StateEntry] ## Mutable authored rows used to construct independent expected maps.

proc batchEnvelope*(ending: BatchEnding): seq[byte] =
  ## Assemble two provides around a checkpoint; instruction bytes and opcode boundaries are independently authored.
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 65536),
    registerImmediate(9, 1), @[10'u8, 27], @[10'u8, 18], registerImmediate(7, 99),
    registerImmediate(8, 196608), @[10'u8, 27]]
  if ending in {BatchEnding.StorageHalt, BatchEnding.StoragePanic,
      BatchEnding.StorageCheckpointPanic}:
    instructions.add(registerImmediate(7, 65536))
    instructions.add(registerImmediate(8, 1))
    instructions.add(registerImmediate(9, 196608))
    instructions.add(registerImmediate(10, 1))
    instructions.add(@[10'u8, 5]) # Existing PVM write PR: one-byte raw key/value in the invoking service.
    if ending == BatchEnding.StorageCheckpointPanic:
      instructions.add(@[10'u8, 18]) # A checkpoint now retains the storage mutation as exceptional state.
  case ending
  of BatchEnding.Halt, BatchEnding.StorageHalt:
    discard # r8 remains an address rather than the exactly-32-byte halt-return length.
  of BatchEnding.Panic, BatchEnding.StoragePanic, BatchEnding.StorageCheckpointPanic:
    instructions.add(@[0'u8]) # Completed guest trap selects the exceptional checkpoint.
  of BatchEnding.Ambiguous:
    instructions.add(registerImmediate(7, 65536))
    instructions.add(registerImmediate(8, 32)) # Preserve the established nonempty-provisions return gate.
  instructions.add(@[50'u8, 0])
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[0, 1, 2, 3, 4]
  for instruction in instructions:
    starts.add(code.len)
    for octet in instruction: code.add(octet) # Arguments are never marked as opcodes.
  assert code.len < 128
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index in starts: mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: raw.add(octet)
  pvmEnvelope(raw)

proc batchInputSet*(incoming = true): PreparedAccumulationInputs =
  ## Equal-content calls create distinct input owners for source-substitution rejection tests.
  let queue = planAccumulationQueues([], [0'u8], [0'u8], HeaderSlot(0),
    AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(1),
      maxBytes: ByteLimit(1000)))).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), default(
      AccumulationOperandConfig)).value
  var transfers: seq[DeferredTransfer] = @[]
  if incoming:
    transfers.add(DeferredTransfer(source: ServiceIndex(1), destination: ServiceIndex(42),
        amount: TransferBalance(7)))
    transfers.add(DeferredTransfer(source: ServiceIndex(2), destination: ServiceIndex(99),
        amount: TransferBalance(11)))
  prepareAccumulationInputs(operands, transfers, [AlwaysAccumulate(service: ServiceIndex(42),
      gas: PrivilegeGas(100000)),
    AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(100000))],
    AccumulationInputConfig(inputs: ElementLimit(2), allowances: ElementLimit(2),
        services: ElementLimit(2))).value

proc batchFixture*(first = BatchEnding.Halt, second = BatchEnding.Halt,
    writes = 64'u64, incoming = true, firstEnvelope: seq[byte] = @[],
    secondEnvelope: seq[byte] = @[], extra: seq[StateEntry] = @[]): BatchFixture =
  ## Capture both ready-code services and independent canonical requests in the same complete immutable prior.
  ## Optional copied envelopes/extra entries authorize cross-host witnesses without changing default callers.
  let config = pvmContextConfig()
  var entries = @[
    authorizationEntry(AuthorizationKind.Queues, @[newSeq[AuthorizerHash](80), newSeq[
        AuthorizerHash](80)], config.queues).value,
    validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](6), config.staging).value,
    privilegeStateEntry(PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)]),
        config.privileges).value,
    StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 8]),
    serviceStorageEntry(ServiceIndex(42), @[1'u8], @[2'u8], ServiceEntryLimits(keyBytes: ByteLimit(
        1), valueBytes: ByteLimit(1))).value,
    provisionRequest(42, @[73'u8]), provisionRequest(99, @[81'u8])]
  for entry in extra:
    entries.add(entry) # Extra integration witnesses enter the same immutable complete source map.
  for index, ending in [first, second]:
    let service = ServiceIndex(if index == 0: 42 else: 99)
    var preimage = @[0'u8]
    let supplied = (if index == 0: firstEnvelope else: secondEnvelope)
    let envelope = (if supplied.len == 0: batchEnvelope(ending) else: supplied)
    for octet in envelope: preimage.add(octet) # Empty metadata framing precedes the entire code envelope.
    let hash = array[32, byte](blake2b256(preimage).value)
    entries.add(serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(hash),
      balance: AccountBalance(if index == 0: 10 else: 20), lastAccumulation: AccountSlot(5)),
          ByteLimit(89)).value)
    entries.add(servicePreimageEntry(service, ServicePreimageHash(hash), preimage,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(preimage.len))).value)
  var limits = integrationStoreLimits(writes = writes)
  result = BatchFixture(inputs: batchInputSet(incoming), entries: entries,
    state: newStateStore(entries, limits).value)

# Preserve the exact original execution profile for default callers, including its independently encoded zero deposits.
proc batchParameters(): Parameters =
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24:
    wire[index] = 0 # Existing tiny-balance fixtures require no deposit funding.
  decodeParameters(wire).value

proc batchExecution*(fixture: BatchFixture, index: uint64, slot = HeaderSlot(128),
    copyLimit = MemoryByteLimit(32), parameters = batchParameters(), transferLimit = ElementLimit(0),
    accountWriteKeys = ElementLimit(0), createdAccounts = ElementLimit(0),
    serviceProbes = ServiceProbeLimit(0), entropy = default(StateEntropyWord)):
    AccumulationDispatchResult =
  ## Prepare and execute exactly one indexed service against the fixture's own immutable input/prior owners.
  ## Explicit copy/profile/outgoing/self-key/creation policies support new integrations; defaults retain the earlier supported path.
  let service = prepareAccumulationService(fixture.inputs, InvocationServiceIndex(index),
    fixture.state.snapshot.value, slot, AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512),
        preimageBytes: ByteLimit(1024))).value
  let invoked = prepareAccumulationInvocation(service, entropy, ServiceProbeLimit(1)).value
  let prepared = initializeAccumulationMachine(invoked, InitializationLimits(
      envelope: InitializationByteLimit(512),
    program: ProgramByteLimit(256), jumps: JumpCountLimit(0), pages: PageLimit(5))).value
  executeAccumulationMachine(prepared, parameters,
    FetchAccumulationLimits(items: ElementLimit(1), bytes: ByteLimit(512),
      operand: OperandLimits(maxBytes: ByteLimit(512))), copyLimit,
    ExecutionStepLimit(200), HostCallLimit(32), GasCycleLimit(10000), pvmContextConfig(),
    provisionPolicy(items = 2, perBlob = 1, total = 2), transferLimit = transferLimit,
    accountWriteKeys = accountWriteKeys, createdAccounts = createdAccounts,
        serviceProbes = serviceProbes)

proc batchPolicy*(accounts = 2'u64, selfWrites = 0'u64,
    selfValueBytes = 0'u64, createdAccounts = 0'u64): AccumulationBatchLimits =
  ## Account and union ceilings remain independent, with the latter including duplicate contributions from both services.
  AccumulationBatchLimits(accounts: ElementLimit(accounts), createdAccounts: ElementLimit(
      createdAccounts), selfWrites: ElementLimit(selfWrites),
    selfValueBytes: ByteLimit(selfValueBytes),
    provisions: integrationPolicy(contexts = 2, items = 4, perBlob = 1, total = 4, encoded = 13))
