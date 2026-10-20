# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed initial rounds and tiny guest programs for complete execution gas accounting.

import ../../src/chain/parameters
import ../../src/state/[accumulation_round, accumulation_inputs, accumulation_operands,
  accumulation_batch, accumulation_queue,
  report_admission,
  accumulation_service, accumulation_invocation, accumulation_machine, accumulation_dispatch,
  accumulation_skip, accumulation_execution, store]
import ../../src/codec/[bounded, composite, header, report_owned, work_digest, state_accounts,
  state_service_values, state_privileges, state_workqueues, state_authorization, state_trie,
  state_safrole, c2_records]
import ../../src/crypto/primitives
import ../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ./[report_context, report_admission_context, pvm_accumulation_context,
  accumulation_provision_integration]

type
  ExecutionEnding* {.pure.} = enum ## Independently authored code and credits distinguish each real terminal alternative.
    Halt,   ## One jump-indirect halt costs 22 gas under the pinned pipeline.
    Panic,  ## Checkpoint followed by trap spends the whole block and checkpoint charges.
    Exhausted, ## An unaffordable basic block leaves its positive gas unchanged under the pinned PVM rule.
    HostExhausted, ## A funded block followed by an underfunded checkpoint produces negative host gas.
    Missing ## Absent code preimage supplies a certified zero-gas skip.
  ExecutionFixture* = object ## Mutable fixture descriptors feed production certificate constructors without replacing verdicts.
    round*: BlockAccumulationRound ## Genuine admitted-parent bound initial plan.
    state*: StateStore             ## Original complete parent map, before any staged block publication.
    entries*: seq[StateEntry]      ## Authored full map for independent equal-root source-substitution tests.

proc executionRoundConfig*(): AccumulationRoundConfig =
  ## Reserve room for two allowance groups and one optional report independently of actual consumption.
  AccumulationRoundConfig(reportGas: Gas(0), blockGas: Gas(300000),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2),
        maxBytes: ByteLimit(1000)),
    operands: AccumulationOperandConfig(reports: ElementLimit(8), operands: ElementLimit(8),
      services: ElementLimit(2), totalBytes: ByteLimit(10000), totalBlobBytes: ByteLimit(10000),
      operand: OperandLimits(outputBytes: ByteLimit(1000), authBytes: ByteLimit(1000),
        totalBlobBytes: ByteLimit(2000), maxBytes: ByteLimit(4000))),
    inputs: AccumulationInputConfig(inputs: ElementLimit(8), allowances: ElementLimit(2),
        services: ElementLimit(2)))

proc executionQueueConfig*(): AccumulationQueueConfig =
  ## Match the genuine tiny chain's core and epoch profile for admitted queue decoding.
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(12),
    perSlot: ElementLimit(8), totalItems: ElementLimit(32), perDependencies: ElementLimit(8),
    totalDependencies: ElementLimit(256), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(
        1000000)),
    items: ElementLimit(32), dependencies: ElementLimit(256))

# Frame an entire service code preimage; a checkpoint's later trap remains in the same charged block.
proc code(ending: ExecutionEnding): seq[byte] =
  result = @[0'u8]
  let envelope = if ending in {ExecutionEnding.Panic, ExecutionEnding.HostExhausted}:
    pvmEnvelope([0'u8, 0, 8, 0, 0, 0, 0, 0, 10, 18, 0, 191])
  else: pvmEnvelope() # Five trap opcodes precede the actual entry-5 halt instruction.
  for octet in envelope: result.add(octet)

proc executionFixture*(base: OwnedReport, first = ExecutionEnding.Halt,
    second = ExecutionEnding.Halt, empty = false, report = false, firstProgram: seq[byte] = @[],
    secondProgram: seq[byte] = @[], allowanceGas = 100000'u64,
    ready: ReadyRow = @[], extra: seq[StateEntry] = @[], secondBalance = 0'u64,
    incomingReports = 0, preimageWire: seq[byte] = @[]): ExecutionFixture =
  ## Recompute parent commitments and real signatures after selecting code, optional complete preimages and free allowances.
  ## Optional allowances, balances and ready rows enter the parent; incoming reports/preimages enter the genuinely signed child.
  let firstCode = (if firstProgram.len == 0: code(first) else: firstProgram)
  let secondCode = (if secondProgram.len == 0: code(second) else: secondProgram)
  var allowances: seq[AlwaysAccumulate] = @[]
  if not empty:
    for ordinal, ending in [first, second]:
      let service = ServiceIndex(if ordinal == 0: 42 else: 99)
      let gas = (if ending == ExecutionEnding.Exhausted: 1'u64 elif ending ==
          ExecutionEnding.HostExhausted: 200'u64 else: allowanceGas)
      allowances.add(AlwaysAccumulate(service: service, gas: PrivilegeGas(gas)))
  let privileges = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2),
    always: allowances), executionRoundConfig().privileges).value
  var entries = @[privileges,
    authorizationEntry(AuthorizationKind.Queues, @[newSeq[AuthorizerHash](80), newSeq[
        AuthorizerHash](80)],
      pvmContextConfig().queues).value]
  for ordinal, raw in [firstCode, secondCode]:
    let service = ServiceIndex(if ordinal == 0: 42 else: 99)
    let hash = array[32, byte](blake2b256(raw).value)
    if ordinal == 1:
      entries.add(serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(hash),
          balance: AccountBalance(secondBalance)), ByteLimit(89)).value)
    let ending = (if ordinal == 0: first else: second)
    if ending != ExecutionEnding.Missing:
      entries.add(servicePreimageEntry(service, ServicePreimageHash(hash), raw,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(raw.len))).value)
  for entry in extra:
    entries.add(entry) # Additional effect witnesses enter the genuine parent before its commitment/signatures.
  let context = authored(base, reports = incomingReports, withAvailable = report, extra = entries,
      accountCode = firstCode, ready = ready, preimageWire = preimageWire)
  let queue = planBlockAccumulationQueue(planBlockReports(context.staged, context.older, config()).value,
    executionQueueConfig()).value
  ExecutionFixture(round: planBlockInitialAccumulation(queue, executionRoundConfig()).value,
    state: context.original, entries: context.source)

proc executionService*(fixture: ExecutionFixture, index: uint64, slot = HeaderSlot(
    2)): PreparedAccumulationService =
  ## Preserve the exact round input owner and explicit fixture parent, allowing genuine foreign-source negative tests.
  prepareAccumulationService(fixture.round.roundProjection.value.roundInputs.value,
      InvocationServiceIndex(index),
    fixture.state.snapshot.value, slot, AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512),
      preimageBytes: ByteLimit(1024))).value

proc executionGuest*(fixture: ExecutionFixture, index: uint64, slot = HeaderSlot(
    2), wrongEntropy = false, parameters: Parameters = pvmParameters(),
    copyLimit = MemoryByteLimit(32), transferLimit = ElementLimit(0),
    steps = ExecutionStepLimit(20), calls = HostCallLimit(4)): AccumulationDispatchResult =
  ## Run the real PVM against one original service; no terminal or gas observation is forged.
  let service = prepareBlockAccumulationService(fixture.round, InvocationServiceIndex(index),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  let bound = prepareBlockAccumulationInvocation(service, ServiceProbeLimit(
      1)).value.bootstrapProjection.value
  var entropy = array[32, byte](bound.bootstrapInfo.value.entropy)
  if wrongEntropy:
    entropy[0] = entropy[0] xor 1 # A real pure invocation can otherwise execute with the wrong block seed.
  let invocation = prepareAccumulationInvocation(executionService(fixture, index, slot),
    StateEntropyWord(entropy), ServiceProbeLimit(1)).value
  let prepared = initializeAccumulationMachine(invocation, InitializationLimits(
    envelope: InitializationByteLimit(512), program: ProgramByteLimit(256), jumps: JumpCountLimit(0),
    pages: PageLimit(5))).value
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  executeAccumulationMachine(prepared, parameters,
    FetchAccumulationLimits(items: ElementLimit(1), bytes: ByteLimit(512), operand: OperandLimits(
        maxBytes: ByteLimit(512))),
    copyLimit, steps, calls, GasCycleLimit(1000), contexts,
    transferLimit = transferLimit)

proc executionSkip*(fixture: ExecutionFixture, index: uint64): SkippedAccumulation =
  ## Certify unavailable code with its retained post-transfer map and exact initial round source owners.
  finishUninvokedAccumulation(executionService(fixture, index)).value

proc executionLimits*(services = 2'u64): AccumulationExecutionLimits =
  ## Gas rows and complete batch metadata/provision preparation have independent local ceilings.
  AccumulationExecutionLimits(services: ElementLimit(services),
    batch: AccumulationBatchLimits(accounts: ElementLimit(2), provisions: integrationPolicy()))
