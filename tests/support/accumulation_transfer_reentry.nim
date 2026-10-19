# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed transfer chains exercise first/repeated reentry, credit once, paid gas, bounded ownership and processed-transfer statistics.

import std/assertions
import ../../src/chain/parameters
import ../../src/codec/[bounded, composite, header, c2_records, report_owned, state_accounts,
  state_service_values, state_layout, state_trie, state_outputs, state_statistics]
import ../../src/state/[accumulation_execution, accumulation_round, accumulation_batch,
  accumulation_continuation, accumulation_continuation_inputs, accumulation_continuation_invocation,
  accumulation_continuation_execution, accumulation_reentry, accumulation_reentry_invocation,
  accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_machine,
  accumulation_dispatch, accumulation_skip, accumulation_transfers, accumulation_provisions,
  accumulation_outputs, accumulation_finalization, accumulation_statistics, store]
import ../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ../../src/crypto/primitives
import ./[accumulation_execution_context, accumulation_reentry_context,
  pvm_accumulation_context, pvm_accumulation_program, report_context, accumulation_account_timestamps]

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
    zeroGas = false, mixed = false, lateOnly = false, missing = false, large = false,
        budget = 200000'u64): TransferFixture =
  ## Initial 42 -> 99 plus duplicated 99 -> 77 funds later 77 -> 88; each round uses actual complete-source execution.
  var halt = @[0'u8]
  for octet in guestEnvelope([@[50'u8, 0]]):
    halt.add(octet) # Service 88 consumes its inputs and emits nothing, ensuring finite real termination.
  let c77 = code(77, 88, 3, if large: high(uint64)-30000 elif zeroGas: 0'u64 else: 10000'u64,
      stop = stop, checkpoint = checkpoint)
  var extra = serviceEntries(77, 10, c77)
  if missing:
    extra.setLen(1) # Preserve metadata and known code hash while withholding its preimage for a genuine skip.
  for entry in serviceEntries(88, 7, halt):
    extra.add(entry) # Both destinations exist before any transfer host lookup.
  let ready = (if lateOnly: @[reentryReady(base, 97, [99999'u64], 99)] elif mixed: @[reentryReady(
      base, 94, [150000'u64], 99), reentryReady(base, 95, [20000'u64], 99),
    reentryReady(base, 96, [0'u64], 99)] else: @[])
  let ending = (if lateOnly: ExecutionEnding.Exhausted else: ExecutionEnding.Halt)
  let secondEnding = (if large: ExecutionEnding.Exhausted else: ending)
  let firstGas = (if large: high(uint64)-10000 elif zeroGas: 0'u64 else: 30000'u64)
  let secondGas = (if large: high(uint64)-20000 elif zeroGas: 0'u64 else: 10000'u64)
  let allowance = (if large: high(uint64)-1 else: 100000'u64)
  var initial = executionFixture(base, first = ending, second = secondEnding,
    firstProgram = code(42, 99, 0, firstGas), secondProgram = code(99, 77, 2, secondGas,
        repeat = not large),
    secondBalance = 20, extra = extra, ready = ready, allowanceGas = allowance)
  var policy = executionRoundConfig()
  policy.blockGas = Gas(if large: high(uint64) elif lateOnly: 100000'u64 else: budget)
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
  assert count == (if lateOnly or large: 1 else: 2)
  var executions: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  for index in countdown(count-1, 0):
    let service = prepareContinuationAccumulationService(context, InvocationServiceIndex(uint64(
        index)),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
    if service.serviceInfo.value.code != AccumulationCodeStatus.Ready:
      skips.add(finishUninvokedAccumulation(service).value) # Missing destinations still receive and process their transfers.
    else:
      let invoked = prepareContinuationAccumulationInvocation(context, InvocationServiceIndex(
          uint64(index)),
        AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024)),
            ServiceProbeLimit(1)).value
      executions.add(run(invoked.bootstrapProjection.value)) # Reverse execution order must not choose outgoing source order.
  TransferFixture(initial: initial, later: completeAccumulationContinuation(context, executions,
      skips, executionLimits()).value)

proc completed(source: PreparedAccumulationReentry): CompletedAccumulationReentry =
  ## Execute every actual reentry group against its own posterior state/entropy, in reversed arrival order.
  let count = source.reentryInputs.value.invocationServiceCount.value
  var executions: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  for index in countdown(count-1, 0):
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
    if service.serviceInfo.value.code != AccumulationCodeStatus.Ready:
      skips.add(finishUninvokedAccumulation(service).value) # Counted input destinations may legitimately skip code execution.
    else:
      let invoked = prepareReentryAccumulationInvocation(source, InvocationServiceIndex(uint64(
          index)),
        AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024)),
        ServiceProbeLimit(1)).value
      executions.add(run(invoked.bootstrapProjection.value)) # No usage, credit or verdict is forged.
  var limits = executionLimits(uint64(count))
  limits.batch.accounts = ElementLimit(uint64(count)) # Mixed rounds can update three distinct service metadata rows.
  completeAccumulationReentry(source, executions, skips, limits).value

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
  ## Independent transfer/gas/report populations bound the genuine history before dictionary preparation.
  AccumulationStatisticsLimits(rounds: ElementLimit(6), gasRows: ElementLimit(10),
      transfers: ElementLimit(10), reports: ElementLimit(2),
    digests: ElementLimit(2), services: ElementLimit(4))

proc finished(source: CompletedAccumulationContinuation): PreparedFinalAccumulation =
  ## Complete the authored finite chain under an explicit depth cap, retaining any selected hash-return outputs.
  var next = prepareAccumulationReentry(source, config()).value
  while next.reentryInfo.value.dispatch:
    # Actual completions alone authorize each successor, including transfer-only and skipped-service rounds.
    next = prepareAccumulationReentry(completed(next), config(), AccumulationReentryDepthLimit(4)).value
  var limits = historyPolicy()
  limits.executions = ElementLimit(16) # Mixed report/transfer rounds can contain three service groups.
  limits.log = OutputLogConfig(items: ElementLimit(10), maxBytes: ByteLimit(1024))
  prepareFinalAccumulation(completed(next), limits).value

proc checkTransferReentry*(base: OwnedReport) =
  ## Exercise genuine transfer chains, destination statistics, rollback, independent limits, real roots and ARC release.
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
  let statistics = prepareAccumulationStatistics(finalized, statisticsPolicy()).value
  assert statistics.statisticsInfo.value.transfers == 7
  assert statistics.statisticsInfo.value.services == 4
  for index, count in [0'u64, 4'u64, 2'u64, 1'u64]:
    let row = statistics.statisticsAt(StatisticsServiceIndex(uint64(index))).value
    assert uint32(row.service) == [42'u32, 77'u32, 88'u32, 99'u32][index]
    assert uint64(row.statistics.counters[ServiceMeasure.TransferCount]) == count
    assert uint64(row.statistics.counters[ServiceMeasure.AccumulationCount]) == 0
  assert hashCalls() == 0
  failHash(0)
  checkAccountTimestamps(statistics, [42'u32, 77'u32, 88'u32, 99'u32])
  let gross = uint64(source.later.executionContinuation.value.continuationPlan.value.continuationSource.value.executionInfo.value.gasUsed) +
    uint64(source.later.executionInfo.value.gasUsed)+uint64(
        firstDone.executionInfo.value.gasUsed)+uint64(secondDone.executionInfo.value.gasUsed)
  assert uint64(statistics.statisticsInfo.value.gasUsed) == gross
  assert gross == 200000-uint64(stopped.reentryInfo.value.budget)+90000, "gross actual gas reconciles only when all selected outgoing gas is restored"
  let initialDone = source.later.executionContinuation.value.continuationPlan.value.continuationSource.value
  let expectedGas = [uint64(initialDone.executionGasAt(InvocationServiceIndex(0)).value.gasUsed),
    uint64(source.later.executionGasAt(InvocationServiceIndex(0)).value.gasUsed)+uint64(
        firstDone.executionGasAt(InvocationServiceIndex(0)).value.gasUsed),
    uint64(firstDone.executionGasAt(InvocationServiceIndex(1)).value.gasUsed)+uint64(
        secondDone.executionGasAt(InvocationServiceIndex(0)).value.gasUsed),
    uint64(initialDone.executionGasAt(InvocationServiceIndex(1)).value.gasUsed)+uint64(
        source.later.executionGasAt(InvocationServiceIndex(1)).value.gasUsed)]
  for index, gas in expectedGas:
    assert uint64(statistics.statisticsAt(StatisticsServiceIndex(uint64(
        index))).value.statistics.accumulationGas) == gas
  var exact = statisticsPolicy()
  exact.rounds = ElementLimit(5)
  exact.gasRows = ElementLimit(7)
  exact.transfers = ElementLimit(7)
  exact.reports = ElementLimit(0)
  exact.digests = ElementLimit(0)
  failHash(3)
  assert prepareAccumulationStatistics(finalized, exact).value.statisticsInfo.value.transfers == 7
  for mode in 0..<5:
    var limited = exact
    case mode
    of 0: limited.transfers = ElementLimit(6) # Exact aggregate cardinality includes duplicates across rounds.
    of 1: limited.transfers = ElementLimit(0) # Default transfer capacity authorizes report-only histories.
    of 2: limited.rounds = ElementLimit(4) # Count the certified stopped entry as well.
    of 3: limited.gasRows = ElementLimit(6) # Every bound input service, including zeros, consumes traversal.
    else: limited.services = ElementLimit(3) # Nonzero statistics includes transfer-only destinations.
    assert prepareAccumulationStatistics(finalized, limited).error ==
        AccumulationStatisticsError.LimitExceeded
  var wide = statisticsPolicy()
  wide.rounds = ElementLimit(high(uint64))
  wide.gasRows = ElementLimit(high(uint64))
  wide.transfers = ElementLimit(high(uint64))
  wide.reports = ElementLimit(high(uint64))
  wide.digests = ElementLimit(high(uint64))
  wide.services = ElementLimit(high(uint64))
  assert prepareAccumulationStatistics(finalized, wide).value.statisticsInfo.value.transfers == 7
  var copied = statistics.statisticsAt(StatisticsServiceIndex(1)).value
  copied.statistics.counters[ServiceMeasure.TransferCount] = ActivityNatural(0)
  var observedStatistics = statistics.statisticsInfo.value
  observedStatistics.transfers = 0
  assert statistics.statisticsInfo.value.transfers == 7
  assert uint64(statistics.statisticsAt(StatisticsServiceIndex(1)).value.statistics.counters[
      ServiceMeasure.TransferCount]) == 4
  assert sameStateSnapshot(statistics.statisticsSource.value.finalAccumulationState.value,
      finalized.finalAccumulationState.value)
  assert hashCalls() == 0
  failHash(0)
  let mixed = fixture(base, mixed = true)
  let mixedPlan = prepareAccumulationReentry(mixed.later, config()).value
  assert uint64(mixedPlan.reentryInfo.value.prefix) == 1 and uint64(
      mixedPlan.reentryInfo.value.reportGas) == 150000
  assert mixedPlan.reentryInputs.value.invocationServiceCount.value == 3
  let group = mixedPlan.reentryInputs.value.invocationServiceAt(InvocationServiceIndex(2)).value
  assert uint32(group.service) == 99 and uint64(group.gas) == 150000 and group.operands == 1
  assert uint64(mixedPlan.reentryInfo.value.transferGas) == 30000, "restored outgoing gas cannot fund an extra report"
  let mixedFinal = finished(mixed.later)
  var mixedPolicy = statisticsPolicy()
  mixedPolicy.reports = ElementLimit(3)
  mixedPolicy.digests = ElementLimit(3)
  mixedPolicy.gasRows = ElementLimit(16)
  failHash(3)
  let mixedActivity = prepareAccumulationStatistics(mixedFinal, mixedPolicy).value
  assert mixedActivity.statisticsInfo.value.transfers == 10
  assert mixedActivity.statisticsInfo.value.reports == 3 and
      mixedActivity.statisticsInfo.value.digests == 3
  for index, count in [0'u64, 6'u64, 3'u64, 1'u64]:
    let row = mixedActivity.statisticsAt(StatisticsServiceIndex(uint64(index))).value
    assert uint64(row.statistics.counters[ServiceMeasure.TransferCount]) == count
    assert uint64(row.statistics.counters[ServiceMeasure.AccumulationCount]) == (if index ==
        3: 3'u64 else: 0'u64)
  assert uint64(mixedActivity.statisticsInfo.value.gasUsed) == 200000-uint64(
      mixedFinal.finalAccumulationInfo.value.remainingGas)+120000
  assert hashCalls() == 0
  failHash(0)
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
      let terminal = finished(local.later)
      failHash(3)
      let activity = prepareAccumulationStatistics(terminal, statisticsPolicy()).value
      assert activity.statisticsInfo.value.transfers == (if kept: 7 else: 5)
      assert uint64(activity.statisticsAt(StatisticsServiceIndex(1)).value.statistics.counters[
          ServiceMeasure.TransferCount]) == 4
      failHash(0)
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
  let zeroStatistics = prepareAccumulationStatistics(zeroFinal, statisticsPolicy()).value
  assert zeroStatistics.statisticsInfo.value.transfers == 3 and
      zeroStatistics.statisticsInfo.value.services == 3
  let zeroDestination = zeroStatistics.statisticsAt(StatisticsServiceIndex(1)).value
  assert uint32(zeroDestination.service) == 77 and uint64(
      zeroDestination.statistics.accumulationGas) == 0
  assert uint64(zeroDestination.statistics.counters[ServiceMeasure.TransferCount]) == 2,
    "zero-gas transfer-only destinations must survive all-zero omission"
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
    let activity = prepareAccumulationStatistics(final, statisticsPolicy()).value
    assert activity.statisticsInfo.value.transfers == (if zeroGas: 2 else: 3)
    assert activity.statisticsInfo.value.reports == 1 and activity.statisticsInfo.value.digests == 1
    let firstRow = activity.statisticsAt(StatisticsServiceIndex(0)).value
    assert uint32(firstRow.service) == 77 and uint64(firstRow.statistics.counters[
        ServiceMeasure.TransferCount]) == 2
    let lastRow = activity.statisticsAt(StatisticsServiceIndex(uint64(
        activity.statisticsInfo.value.services-1))).value
    assert uint32(lastRow.service) == 99 and uint64(lastRow.statistics.counters[
        ServiceMeasure.AccumulationCount]) == 1
    assert hashCalls() == 0
    failHash(0)
  var detachedStatistics = default(PreparedAccumulationStatistics)
  block released_statistics_callers:
    # A missing code preimage preserves input credit/counts through genuine skips in both later rounds.
    let skipped = fixture(base, missing = true)
    let final = finished(skipped.later)
    failHash(3)
    detachedStatistics = prepareAccumulationStatistics(final, statisticsPolicy()).value
    failHash(0)
    sameRoot(skipped.initial, final.finalAccumulationOutputs.value.outputsReentry.value.executionReentry.value.reentryState.value,
        12, 18, 7)
  assert detachedStatistics.statisticsInfo.value.transfers == 5 and
      detachedStatistics.statisticsInfo.value.services == 3
  let skippedRow = detachedStatistics.statisticsAt(StatisticsServiceIndex(1)).value
  assert uint32(skippedRow.service) == 77 and uint64(skippedRow.statistics.accumulationGas) == 0
  assert uint64(skippedRow.statistics.counters[ServiceMeasure.TransferCount]) == 4
  checkAccountTimestamps(zeroStatistics, [42'u32, 77'u32, 99'u32])
  checkAccountTimestamps(detachedStatistics, [42'u32, 77'u32, 99'u32])
  let enormous = finished(fixture(base, large = true).later)
  failHash(3)
  assert prepareAccumulationStatistics(enormous, wide).error ==
      AccumulationStatisticsError.LimitExceeded,
    "valid repeated paid gas can exceed the uint64 aggregate representation and must not wrap"
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
    let activity = prepareAccumulationStatistics(finalized, exact).value
    assert activity.statisticsInfo.value.transfers == 7
    var limited = exact
    limited.transfers = ElementLimit(6)
    assert prepareAccumulationStatistics(finalized, limited).error ==
        AccumulationStatisticsError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after, "repeated transfer owners, predecessors, private maps and memos release across 1000 real cycles"
