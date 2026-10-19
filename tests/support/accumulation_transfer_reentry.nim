# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed transfer chains exercise first/repeated reentry, credit once, paid gas, bounded ownership and statistics scope.

import std/assertions
import ../../src/chain/parameters
import ../../src/codec/[bounded, composite, header, c2_records, report_owned, state_accounts,
  state_service_values, state_layout, state_trie, state_outputs]
import ../../src/state/[accumulation_execution, accumulation_round, accumulation_batch,
  accumulation_continuation, accumulation_continuation_inputs, accumulation_continuation_invocation,
  accumulation_continuation_execution, accumulation_reentry, accumulation_reentry_invocation,
  accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_machine,
  accumulation_dispatch, accumulation_skip, accumulation_transfers, accumulation_provisions,
  accumulation_outputs, accumulation_finalization, accumulation_statistics, store]
import ../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ../../src/crypto/primitives
import ./[accumulation_execution_context, accumulation_reentry_context,
  pvm_accumulation_context, pvm_accumulation_program, report_context]

# Observe preparation's private account phase without replacing guest execution, source certificates or backend verdicts.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

type
  TransferStop {.pure.} = enum ## Only service 77 changes terminal instructions; service 99's duplicate outputs remain regular.
    Halt, Panic, Fault, OutOfGas, HashReturn
  TransferFixture = object ## Test-only descriptors retain the original full map and actual completed continuation.
    initial: ExecutionFixture
    later: CompletedAccumulationContinuation

proc profile(): Parameters =
  ## Tiny balances use zero deposits; actual transfer memory is still exactly 128 opaque octets.
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # Clear all deposit limbs before real host funding validation.
  for index in 110..<114:
    bytes[index] = 0 # Initialize the whole E4 memo width.
  bytes[110] = 128
  decodeParameters(bytes).value

proc code(service, destination: uint32, amount, gas: uint64, repeat = false,
    stop = TransferStop.Halt, checkpoint = false): seq[byte] =
  ## Emit exact duplicate transfers around optional checkpoint/terminal instructions, using the maintained guest framing.
  var memo = newSeq[byte](128)
  for index in 0..<128:
    memo[index] = byte((index*7+int(service)) mod 256) # Every source has an independently recognizable complete memo.
  var instructions = @[registerImmediate(7, uint64(destination)), registerImmediate(8, amount),
    registerImmediate(9, gas), registerImmediate(10, 196608), @[10'u8, 21]]
  if checkpoint:
    instructions.add(@[10'u8, 18]) # Select the first debit/outgoing record in Y before later failure.
  if repeat:
    instructions.add(registerImmediate(7, uint64(destination)))
    instructions.add(@[10'u8, 21]) # Preserve identical amount/gas/memo while making two separate debits.
  case stop
  of TransferStop.Halt:
    discard # Regular halt keeps every completed transfer.
  of TransferStop.Panic:
    instructions.add(@[0'u8]) # Actual trap selects Y.
  of TransferStop.Fault:
    instructions.add(@[52'u8, 2, 0, 0, 4]) # Unmapped load selects the same exceptional checkpoint.
  of TransferStop.OutOfGas:
    instructions.add(registerImmediate(7, uint64(destination)))
    instructions.add(registerImmediate(9, 20000))
    instructions.add(@[10'u8, 21]) # Valid proposal exceeds the later service's remaining gas before another debit.
  of TransferStop.HashReturn:
    instructions.add(registerImmediate(7, 65536))
    instructions.add(registerImmediate(8, 32)) # Hash-return normalization retains X's outgoing records.
  instructions.add(@[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memo):
    result.add(octet) # Empty metadata framing precedes the complete PVM envelope.

proc serviceEntries(service: uint32, balance: uint64, raw: seq[byte]): seq[StateEntry] =
  ## Extra ready services enter the original parent before its real root and signatures are built.
  let digest = array[32, byte](blake2b256(raw).value)
  @[serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(codeHash: CodeHash(digest),
    balance: AccountBalance(balance)), ByteLimit(89)).value,
    servicePreimageEntry(ServiceIndex(service), ServicePreimageHash(digest), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(raw.len))).value]

proc run(invocation: PreparedAccumulationInvocation): AccumulationDispatchResult =
  ## Execute only source-derived bootstraps with finite transfer/memo/C.2 budgets and the real engine.
  let machine = initializeAccumulationMachine(invocation, InitializationLimits(
    envelope: InitializationByteLimit(512), program: ProgramByteLimit(256), jumps: JumpCountLimit(
        0), pages: PageLimit(5))).value
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  executeAccumulationMachine(machine, profile(), FetchAccumulationLimits(items: ElementLimit(3),
      bytes: ByteLimit(1024),
    operand: OperandLimits(maxBytes: ByteLimit(512))), MemoryByteLimit(128), ExecutionStepLimit(100),
    HostCallLimit(10), GasCycleLimit(1000), contexts, transferLimit = ElementLimit(3))

proc config(): AccumulationReentryConfig =
  ## Empty report ranges need no report work; mixed cases reserve both successful and rejected inspections.
  var inputs = executionRoundConfig().inputs
  inputs.services = ElementLimit(3) # Two transferred destinations plus a newly selected report-only service.
  AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(3),
      transfers: ElementLimit(3),
    memoBytes: ByteLimit(384), reports: ElementLimit(2), digests: ElementLimit(2)),
    operands: executionRoundConfig().operands, inputs: inputs)

proc fixture(base: OwnedReport, stop = TransferStop.Halt, checkpoint = false,
    zeroGas = false, mixed = false, lateOnly = false, budget = 200000'u64): TransferFixture =
  ## Initial 42 -> 99 plus duplicated 99 -> 77 funds later 77 -> 88; each round uses actual complete-source execution.
  var halt = @[0'u8]
  for octet in guestEnvelope([@[50'u8, 0]]):
    halt.add(octet) # Service 88 consumes its inputs and emits nothing, ensuring finite real termination.
  let c77 = code(77, 88, 3, if zeroGas: 0'u64 else: 10000'u64, stop = stop, checkpoint = checkpoint)
  var extra = serviceEntries(77, 10, c77)
  for entry in serviceEntries(88, 7, halt):
    extra.add(entry) # Both destinations exist before any transfer host lookup.
  let ready = (if lateOnly: @[reentryReady(base, 97, [99999'u64], 99)] elif mixed: @[reentryReady(
      base, 94, [150000'u64], 99), reentryReady(base, 95, [20000'u64], 99),
    reentryReady(base, 96, [0'u64], 99)] else: @[])
  let ending = (if lateOnly: ExecutionEnding.Exhausted else: ExecutionEnding.Halt)
  var initial = executionFixture(base, first = ending, second = ending, firstProgram = code(42, 99,
      0, if zeroGas: 0'u64 else: 30000'u64),
    secondProgram = code(99, 77, 2, if zeroGas: 0'u64 else: 10000'u64, repeat = true),
    secondBalance = 20, extra = extra, ready = ready)
  var policy = executionRoundConfig()
  policy.blockGas = Gas(if lateOnly: 100000'u64 else: budget)
  initial.round = planBlockInitialAccumulation(initial.round.roundBlockQueue.value, policy).value
  let a = executionGuest(initial, 0, parameters = profile(), copyLimit = MemoryByteLimit(128),
    transferLimit = ElementLimit(3), steps = ExecutionStepLimit(100), calls = HostCallLimit(10))
  let b = executionGuest(initial, 1, parameters = profile(), copyLimit = MemoryByteLimit(128),
    transferLimit = ElementLimit(3), steps = ExecutionStepLimit(100), calls = HostCallLimit(10))
  let done = completeBlockAccumulation(initial.round, [b, a], [], executionLimits()).value
  let selected = planAccumulationContinuation(done, config().selection).value
  let context = prepareAccumulationContinuationInputs(selected, AccumulationContinuationInputConfig(
    operands: policy.operands, inputs: policy.inputs)).value
  assert uint64(selected.continuationInfo.value.prefix) == (if lateOnly: 1'u64 else: 0'u64)
  let count = context.continuationInputs.value.invocationServiceCount.value
  assert count == (if lateOnly: 1 else: 2)
  var executions: seq[AccumulationDispatchResult] = @[]
  for index in countdown(count-1, 0):
    let invoked = prepareContinuationAccumulationInvocation(context, InvocationServiceIndex(uint64(
        index)),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024)),
          ServiceProbeLimit(1)).value
    executions.add(run(invoked.bootstrapProjection.value)) # Reverse execution order must not choose outgoing source order.
  TransferFixture(initial: initial, later: completeAccumulationContinuation(context, executions, [],
      executionLimits()).value)

proc completed(source: PreparedAccumulationReentry): CompletedAccumulationReentry =
  ## Execute every actual reentry group against its own posterior state/entropy, in reversed arrival order.
  let count = source.reentryInputs.value.invocationServiceCount.value
  var executions: seq[AccumulationDispatchResult] = @[]
  for index in countdown(count-1, 0):
    let invoked = prepareReentryAccumulationInvocation(source, InvocationServiceIndex(uint64(
        index)),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024)),
          ServiceProbeLimit(1)).value
    executions.add(run(invoked.bootstrapProjection.value)) # No gas observation, incoming credit or verdict is forged.
  completeAccumulationReentry(source, executions, [], executionLimits(uint64(count))).value

proc balance(state: StateStoreSnapshot, service: uint32): uint64 =
  ## Read exact canonical balances from the retained complete map.
  uint64(decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      service))).value.bytes, ByteLimit(89)).value.metadata.balance)

proc sameRoot(source: ExecutionFixture, state: StateStoreSnapshot, b99, b77, b88: uint64) =
  ## Independently replace only literal balances in the original full rows, preserving code, chapters and unrelated metadata.
  var rows: seq[StateEntry] = @[]
  for entry in source.entries:
    var copied = StateEntry(key: entry.key, value: entry.value)
    for service in [99'u32, 77'u32, 88'u32]:
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        var metadata = decodeServiceMetadata(entry.value, ByteLimit(89)).value.metadata
        metadata.balance = AccountBalance(if service == 99: b99 elif service == 77: b77 else: b88)
        copied = serviceMetadataEntry(ServiceIndex(service), metadata, ByteLimit(89)).value
    rows.add(copied) # Expected roots include every unrelated original mapping.
  let wanted = newStateStore(rows, report_context.limits()).value
  assert array[32, byte](state.commitment.root) == array[32, byte](
      wanted.snapshot.value.commitment.root), "exact independently authored complete-map root"

proc historyPolicy(): AccumulationOutputHistoryLimits =
  ## Bound the entire real chain including its certified stopped entry, with no yielded output pairs in the main fixture.
  AccumulationOutputHistoryLimits(rounds: ElementLimit(6), executions: ElementLimit(10),
    log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))

proc statisticsPolicy(): AccumulationStatisticsLimits =
  ## A scope refusal must precede report-only aggregation, not depend on accidentally exceeding unrelated ceilings.
  AccumulationStatisticsLimits(rounds: ElementLimit(6), gasRows: ElementLimit(10),
      reports: ElementLimit(2),
    digests: ElementLimit(2), services: ElementLimit(4))

proc checkTransferReentry*(base: OwnedReport) =
  ## Exercise first and repeated transfer-only advances, terminal rollback, limits, real roots and fresh ARC release.
  let source = fixture(base)
  let first = prepareAccumulationReentry(source.later, config()).value
  let firstInfo = first.reentryInfo.value
  assert firstInfo.transfers == 3 and uint64(firstInfo.transferGas) == 30000 and firstInfo.dispatch
  assert uint64(firstInfo.prefix) == 0 and uint64(firstInfo.completedPrefix) == 0 and uint64(
      firstInfo.depth) == 1
  assert uint64(firstInfo.budget) == uint64(source.later.executionInfo.value.round.budget)-uint64(
      source.later.executionInfo.value.gasUsed)+30000
  sameRoot(source.initial, first.reentryState.value, 12, 11, 7)
  assert first.reentryPrevious.error == AccumulationReentryError.NoPrevious
  let values = first.reentryTransfers.value
  for index, service in [77'u32, 99'u32, 99'u32]:
    let value = values.collectedTransferAt(CollectedTransferIndex(uint64(index))).value
    assert uint32(value.source) == service
    assert uint32(value.destination) == (if index == 0: 88'u32 else: 77'u32)
    assert uint64(value.amount) == (if index == 0: 3'u64 else: 2'u64) and uint64(value.gas) == 10000
    let memo = array[128, byte](value.memo)
    for offset in 0..<128:
      assert memo[offset] == byte((offset*7+int(service)) mod 256) # Exact duplicate memos remain independent records.
  let inputs = first.reentryInputs.value
  assert inputs.invocationServiceCount.value == 2
  assert uint32(inputs.invocationServiceAt(InvocationServiceIndex(0)).value.service) == 77
  assert inputs.invocationServiceAt(InvocationServiceIndex(0)).value.transfers == 2
  assert uint32(inputs.invocationServiceAt(InvocationServiceIndex(1)).value.service) == 88
  let credited = prepareReentryAccumulationService(first, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  assert balance(credited.serviceState.value, 77) == 15 and balance(first.reentryState.value, 77) == 11
  let firstDone = completed(first)
  let second = prepareAccumulationReentry(firstDone, config(), AccumulationReentryDepthLimit(3)).value
  let secondInfo = second.reentryInfo.value
  assert uint64(secondInfo.depth) == 2 and secondInfo.transfers == 1 and uint64(
      secondInfo.transferGas) == 10000
  assert uint64(secondInfo.prefix) == 0 and secondInfo.dispatch
  assert uint64(secondInfo.budget) == uint64(firstInfo.budget)-uint64(
      firstDone.executionInfo.value.gasUsed)+10000
  sameRoot(source.initial, second.reentryState.value, 12, 12, 10)
  assert sameAccumulationInputs(second.reentryPrevious.value.executionReentry.value.reentryInputs.value,
      first.reentryInputs.value)
  assert sameAccumulationInputs(second.reentrySource.value.executionContinuation.value.continuationInputs.value,
    source.later.executionContinuation.value.continuationInputs.value)
  let secondDone = completed(second)
  let stopped = prepareAccumulationReentry(secondDone, config(), AccumulationReentryDepthLimit(3)).value
  assert not stopped.reentryInfo.value.dispatch and stopped.reentryInfo.value.transfers == 0
  assert uint64(stopped.reentryInfo.value.depth) == 3 and uint64(
      stopped.reentryInfo.value.completedPrefix) == 0
  sameRoot(source.initial, stopped.reentryState.value, 12, 12, 13)
  let terminal = completed(stopped)
  failHash(1)
  assert prepareAccumulationReentry(terminal, config(), AccumulationReentryDepthLimit(10)).error ==
      AccumulationReentryError.Stopped
  assert prepareAccumulationReentry(firstDone, config(), AccumulationReentryDepthLimit(1)).error ==
      AccumulationReentryError.LimitExceeded
  assert hashCalls() == 0
  failHash(0)
  let finalized = prepareFinalAccumulation(terminal, historyPolicy()).value
  failHash(1)
  assert prepareAccumulationStatistics(finalized, statisticsPolicy()).error ==
      AccumulationStatisticsError.UnsupportedTransfers
  assert hashCalls() == 0
  failHash(0)
  let gross = uint64(source.later.executionContinuation.value.continuationPlan.value.continuationSource.value.executionInfo.value.gasUsed) +
    uint64(source.later.executionInfo.value.gasUsed)+uint64(
        firstDone.executionInfo.value.gasUsed)+uint64(secondDone.executionInfo.value.gasUsed)
  assert gross == 200000-uint64(stopped.reentryInfo.value.budget)+90000, "gross actual gas reconciles only when all selected outgoing gas is restored"
  let mixed = fixture(base, mixed = true)
  let mixedPlan = prepareAccumulationReentry(mixed.later, config()).value
  assert uint64(mixedPlan.reentryInfo.value.prefix) == 1 and uint64(
      mixedPlan.reentryInfo.value.reportGas) == 150000
  assert mixedPlan.reentryInputs.value.invocationServiceCount.value == 3
  let group = mixedPlan.reentryInputs.value.invocationServiceAt(InvocationServiceIndex(2)).value
  assert uint32(group.service) == 99 and uint64(group.gas) == 150000 and group.operands == 1
  assert uint64(mixedPlan.reentryInfo.value.transferGas) == 30000, "restored outgoing gas cannot fund an extra report"
  let prior = source.later.executionContinuation.value.continuationState.value
  for mode in 0..<5:
    var limited = config()
    case mode
    of 0: limited.selection.executions = ElementLimit(1) # Bound both completed service outcomes.
    of 1: limited.selection.transfers = ElementLimit(2) # Duplicate transfers consume separate record budgets.
    of 2: limited.selection.memoBytes = ByteLimit(383) # Every one of the three fixed memos needs 128 bytes.
    of 3: limited.inputs.inputs = ElementLimit(2) # Refuse transfer descriptors before state work.
    else: limited.inputs.services = ElementLimit(1) # A late destination-union group also consumes capacity.
    failHash(1)
    let refused = prepareAccumulationReentry(source.later, limited)
    if mode < 3:
      assert refused.error == AccumulationReentryError.LimitExceeded
    else:
      assert refused.error == AccumulationReentryError.InputFailure and refused.inputError ==
          AccumulationInputError.LimitExceeded
    assert hashCalls() == 0
    failHash(0)
  for successful in [0, 2]:
    hashAfter(cint(successful))
    let refused = prepareAccumulationReentry(source.later, config())
    assert refused.error == AccumulationReentryError.BatchFailure and
        refused.batchFailure.storeError == StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(prior, source.later.executionContinuation.value.continuationState.value)
  for stop in [TransferStop.Halt, TransferStop.HashReturn, TransferStop.Panic, TransferStop.Fault,
      TransferStop.OutOfGas]:
    for checkpoint in [false, true]:
      let local = fixture(base, stop, checkpoint)
      let selected = prepareAccumulationReentry(local.later, config()).value
      let kept = stop in {TransferStop.Halt, TransferStop.HashReturn} or checkpoint
      assert selected.reentryInfo.value.transfers == (if kept: 3 else: 2)
      assert uint64(selected.reentryInfo.value.transferGas) == (if kept: 30000'u64 else: 20000'u64)
      sameRoot(local.initial, selected.reentryState.value, 12, (if kept: 11'u64 else: 14'u64), 7)
  let maximum = fixture(base, budget = high(uint64))
  let maximumInfo = prepareAccumulationReentry(maximum.later, config()).value.reentryInfo.value
  assert uint64(maximumInfo.budget) == uint64(maximum.later.executionInfo.value.round.budget) -
    (uint64(maximum.later.executionInfo.value.gasUsed)-30000), "subtract spent gas before bounded restoration near uint64 maximum"
  let zeros = fixture(base, zeroGas = true)
  assert zeros.later.executionInfo.value.round.transfers == 3 and
      zeros.later.executionInfo.value.round.dispatch
  let zeroPlan = prepareAccumulationReentry(zeros.later, config()).value
  assert not zeroPlan.reentryInfo.value.dispatch
  sameRoot(zeros.initial, zeroPlan.reentryState.value, 16, 14, 7)
  let zeroFinal = prepareFinalAccumulation(completed(zeroPlan), historyPolicy()).value
  failHash(1)
  assert prepareAccumulationStatistics(zeroFinal, statisticsPolicy()).error ==
      AccumulationStatisticsError.UnsupportedTransfers,
    "even zero-gas processed transfers must not silently become zero transfer statistics"
  failHash(0)
  for zeroGas in [false, true]:
    # Initial allowance OOG emits nothing; only the selected continuation report starts this chain.
    let late = fixture(base, zeroGas = zeroGas, lateOnly = true)
    assert late.later.executionInfo.value.round.transfers == 0
    var next = prepareAccumulationReentry(late.later, config()).value
    assert next.reentryInfo.value.transfers == 2 and next.reentryInfo.value.dispatch
    while next.reentryInfo.value.dispatch:
      # Actual completed rounds retain incoming records even when their gas allowance is zero.
      next = prepareAccumulationReentry(completed(next), config(), AccumulationReentryDepthLimit(4)).value
    let final = prepareFinalAccumulation(completed(next), historyPolicy()).value
    if zeroGas:
      sameRoot(late.initial, next.reentryState.value, 16, 14, 7)
    failHash(1)
    assert prepareAccumulationStatistics(final, statisticsPolicy()).error ==
        AccumulationStatisticsError.UnsupportedTransfers,
      "later-only processed transfers must be detected through the retained reentry history"
    assert hashCalls() == 0
    failHash(0)
  let absent = default(PreparedAccumulationReentry)
  assert absent.reentryTransfers.error == AccumulationReentryError.Uninitialized
  var observed = firstInfo
  observed.transfers = 0
  observed.transferGas = Gas(0)
  assert first.reentryInfo.value.transfers == 3 and uint64(first.reentryInfo.value.transferGas) == 30000
  var detached = default(PreparedAccumulationReentry)
  block released_callers:
    let local = fixture(base)
    detached = prepareAccumulationReentry(local.later, config()).value
  assert detached.reentryTransfers.value.transferCollectionInfo.value.transfers == 3
  assert balance(detached.reentryState.value, 99) == 12
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let selected = prepareAccumulationReentry(source.later, config()).value
    let done = completed(selected)
    let next = prepareAccumulationReentry(done, config(), AccumulationReentryDepthLimit(3)).value
    assert next.reentryInfo.value.transfers == 1 and uint64(next.reentryInfo.value.depth) == 2
    assert balance(next.reentryState.value, 88) == 10
  let after = getOccupiedMem()
  assert before == after, "repeated transfer owners, predecessors, private maps and memos release across 1000 real cycles"
