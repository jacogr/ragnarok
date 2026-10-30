# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed initial rounds and tiny guest programs for complete execution gas accounting.

import ../../src/chain/parameters
import ../../src/state/accumulation/[round as accumulation_round, inputs as accumulation_inputs,
    operands as accumulation_operands, batch as accumulation_batch, queue as accumulation_queue]
import ../../src/state/report/admission as report_admission
import ../../src/state/accumulation/[service as accumulation_service,
    invocation as accumulation_invocation, machine as accumulation_machine,
    dispatch as accumulation_dispatch, skip as accumulation_skip,
    execution as accumulation_execution, effects as accumulation_effects]
import ../../src/state/store
import ../../src/codec/[bounded, composite, header, report_owned]
import ../../src/codec/work/digest as work_digest
import ../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    privileges as state_privileges, workqueues as state_workqueues,
    authorization as state_authorization, trie as state_trie, safrole as state_safrole,
    history as state_history]
import ../../src/codec/c2_records
import ../../src/crypto/primitives
import ../../src/pvm/[initialize, machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/host/fetch as host_fetch
import ./[report_context, report_admission_context, pvm_accumulation_context,
  accumulation_provision_integration]

export report_admission_context.SignedBlockFixtureConfig

type
  ExecutionEnding* {.pure.} = enum ## Independently authored code and credits distinguish each real terminal alternative.
    Halt,   ## One jump-indirect halt costs 22 gas under the pinned pipeline.
    Panic,  ## Checkpoint followed by trap spends the whole block and checkpoint charges.
    Exhausted, ## An unaffordable basic block leaves its positive gas unchanged under the pinned PVM rule.
    HostExhausted, ## A funded block followed by an underfunded checkpoint drains remaining host gas to zero.
    Missing ## Absent code preimage supplies a certified zero-gas skip.
  ExecutionFixture* = object ## Mutable fixture descriptors feed production certificate constructors without replacing verdicts.
    round*: BlockAccumulationRound ## Genuine admitted-parent bound initial plan.
    state*: StateStore             ## Original complete parent map, before any staged block publication.
    entries*: seq[StateEntry]      ## Authored full map for independent equal-root source-substitution tests.
    older*: seq[OwnedHeader]       ## Original signed lookup headers used by genuine report admission.

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
    pvmEnvelope([0'u8, 0, 8, 0, 0, 0, 0, 0, 10, 19, 0, 191])
  else: pvmEnvelope() # Five trap opcodes precede the actual entry-5 halt instruction.
  for octet in envelope: result.add(octet)

type ExecutionFixtureConfig* = object ## PVM guest choices own execution data and retain one shared signed-block configuration.
  first*: ExecutionEnding           ## First guest terminal behavior when no custom program is supplied.
  second*: ExecutionEnding          ## Second guest terminal behavior when no custom program is supplied.
  empty*: bool                      ## Omit both always-accumulate allowances.
  firstProgram*: seq[byte]          ## Optional complete first-service code preimage.
  secondProgram*: seq[byte]         ## Optional complete second-service code preimage.
  allowanceGas*: uint64             ## Gas assigned to each ordinary always-accumulate service.
  secondSupervisor*: uint32         ## Genuine prior supervisor for conflict/provision integration witnesses.
  secondSupervisorBalance*: uint64  ## Original protected balance for explicit source-pool witnesses.
  secondBalance*: uint64            ## Original balance of the second service.
  assigner*: uint32                 ## Original assigner service for both cores.
  authorizationQueue*: seq[byte]    ## Optional exact C(2), including malformed-state witnesses.
  omitAuthorizationQueue*: bool     ## Omit original C(2) for missing-state witnesses.
  manager*: uint32                  ## Original manager service.
  registrar*: uint32                ## Original reserved-service allocation authority.
  delegator*: uint32                ## Original validator-staging authority.
  signed*: SignedBlockFixtureConfig ## Same state-owned configuration used by signed block witnesses.

proc executionFixtureConfig*(): ExecutionFixtureConfig =
  ## Preserve existing guest defaults and the no-incoming-report signed profile.
  var signed = signedBlockFixtureConfig()
  signed.reports = 0
  ExecutionFixtureConfig(first: ExecutionEnding.Halt, second: ExecutionEnding.Halt, empty: false,
      firstProgram: @[], secondProgram: @[], allowanceGas: 100000'u64, secondBalance: 0'u64,
          secondSupervisor: 0'u32,
      assigner: 0'u32, authorizationQueue: @[], omitAuthorizationQueue: false, manager: 0'u32,
      registrar: 0'u32, delegator: 0'u32, signed: signed)

proc executionFixture*(base: OwnedReport, options = executionFixtureConfig()): ExecutionFixture =
  ## Recompute parent commitments and real signatures after selecting code, optional complete preimages and free allowances.
  ## Optional allowances, balances, ready rows and belt peaks enter the parent; incoming reports/preimages enter the genuinely signed child.
  let firstCode = (if options.firstProgram.len == 0: code(options.first) else: options.firstProgram)
  let secondCode = (if options.secondProgram.len == 0: code(
      options.second) else: options.secondProgram)
  var allowances: seq[AlwaysAccumulate] = @[]
  if not options.empty:
    for ordinal, ending in [options.first, options.second]:
      let service = ServiceIndex(if ordinal == 0: 42 else: 99)
      let gas = (if ending == ExecutionEnding.Exhausted: 1'u64 elif ending ==
          ExecutionEnding.HostExhausted: 200'u64 else: options.allowanceGas)
      allowances.add(AlwaysAccumulate(service: service, gas: PrivilegeGas(gas)))
  var assigners = newSeq[ServiceIndex](2)
  for index in 0..<assigners.len: assigners[index] = ServiceIndex(
      options.assigner) # Optional authority enters the signed parent before real assign calls.
  let privileges = privilegeStateEntry(PrivilegeState(manager: ServiceIndex(options.manager),
      delegator: ServiceIndex(options.delegator), registrar: ServiceIndex(options.registrar),
          assigners: assigners,
    always: allowances), executionRoundConfig().privileges).value
  var entries = @[privileges]
  if not options.omitAuthorizationQueue:
    let queues = authorizationEntry(AuthorizationKind.Queues, @[newSeq[AuthorizerHash](80), newSeq[
        AuthorizerHash](80)], pvmContextConfig().queues).value
    entries.add(StateEntry(key: queues.key, value: (if options.authorizationQueue.len == 0:
      queues.value else: options.authorizationQueue))) # Explicit malformed fixtures are committed honestly before the tested decoder stage.
  for ordinal, raw in [firstCode, secondCode]:
    let service = ServiceIndex(if ordinal == 0: 42 else: 99)
    let hash = array[32, byte](blake2b256(raw).value)
    if ordinal == 1:
      entries.add(serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(hash),
          balance: AccountBalance(options.secondBalance),
          supervisorBalance: AccountBalance(options.secondSupervisorBalance),
          supervisor: ServiceIndex(options.secondSupervisor)), ByteLimit(
              ServiceMetadataBytes)).value)
    let ending = (if ordinal == 0: options.first else: options.second)
    if ending != ExecutionEnding.Missing:
      entries.add(servicePreimageEntry(service, ServicePreimageHash(hash), raw,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(raw.len))).value)
  for entry in options.signed.extra:
    entries.add(entry) # Additional effect witnesses enter the genuine parent before its commitment/signatures.
  var signed = options.signed
  signed.extra = entries
  signed.accountCode = firstCode
  let context = authored(base, signed)
  let queue = planBlockAccumulationQueue(planBlockReports(context.staged, context.older, config()).value,
    executionQueueConfig()).value
  ExecutionFixture(round: planBlockInitialAccumulation(queue, executionRoundConfig()).value,
    state: context.original, entries: context.source, older: context.older)

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
    steps = ExecutionStepLimit(20), calls = HostCallLimit(4),
    provisions = default(AccumulationProvisionLimits)): AccumulationDispatchResult =
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
    copyLimit, steps, calls, GasCycleLimit(1000), contexts, provisions,
    transferLimit = transferLimit)

proc executionSkip*(fixture: ExecutionFixture, index: uint64): SkippedAccumulation =
  ## Certify unavailable code with its retained post-transfer map and exact initial round source owners.
  finishUninvokedAccumulation(executionService(fixture, index)).value

proc executionLimits*(services = 2'u64): AccumulationExecutionLimits =
  ## Gas rows and complete batch metadata/provision preparation have independent local ceilings.
  AccumulationExecutionLimits(services: ElementLimit(services),
    batch: AccumulationBatchLimits(accounts: ElementLimit(2), provisions: integrationPolicy()))
