# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real admitted transfer rounds verify canonical collection, recursive gas reservation and posterior service input binding.

import std/assertions
import ../../src/chain/parameters
import ../../src/codec/[bounded, composite, header, c2_records, report_owned, owned,
  work_report, work_digest, state_accounts, state_service_values, state_layout, state_workqueues, state_trie]
import ../../src/state/[accumulation_execution, accumulation_round, accumulation_batch,
  accumulation_dispatch, accumulation_skip, accumulation_outcome, accumulation_context,
  accumulation_transfers, accumulation_round_transfers, accumulation_continuation,
  accumulation_continuation_inputs, accumulation_inputs, accumulation_service,
  accumulation_operands,
  accumulation_provisions, store]
import ../../src/pvm/[machine, step]
import ./[accumulation_execution_context, pvm_accumulation_context, pvm_accumulation_program, report_context]

# Collection/planning does no hashing; input binding's actual private state application may refuse atomically.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type
  TransferStop {.pure.} = enum ## Each choice drives genuine terminal selection, never caller-authored outcome flags.
    Halt, Panic, Fault, OutOfGas, HashReturn

proc profile(): Parameters =
  ## Zero deposits support the literal tiny balances while preserving the exact 128-byte transfer memo profile.
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # Set complete deposit words, avoiding stale high limbs.
  for index in 110..<114:
    bytes[index] = 0 # Initialize the complete E4 memo-width field.
  bytes[110] = 128
  decodeParameters(bytes).value

proc code(first: bool, stop = TransferStop.Halt, checkpoint = true, zeroGas = false): seq[byte] =
  ## Service 42 emits two zero-amount records to 99; funded service 99 emits five units to previously uninvoked 77.
  var memo = newSeq[byte](128)
  for index in 0..<128:
    memo[index] = byte((index*7+(if first: 3 else: 11)) mod 256) # Distinct opaque memos prove numeric source order.
  let destination = (if first: 99'u64 else: 77'u64)
  let gas = (if zeroGas: 0'u64 else: (if first: 3'u64 else: 7'u64))
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, destination),
    @[51'u8, 9, 0], registerImmediate(10, if first: 0'u64 else: 5'u64),
    registerImmediate(11, gas), registerImmediate(12, 196608), @[10'u8, 22]]
  if first and checkpoint:
    instructions.add(@[10'u8, 19]) # Only the first record belongs to Y.
  if first:
    instructions.add(registerImmediate(7, high(uint64)))
    instructions.add(@[10'u8, 22]) # Duplicate records remain separate selected inputs and paid gas.
    case stop
    of TransferStop.Halt:
      discard # Ordinary halt retains both regular appends.
    of TransferStop.Panic:
      instructions.add(@[0'u8]) # A genuine trap selects Y.
    of TransferStop.Fault:
      instructions.add(@[52'u8, 2, 0, 0, 4]) # Physical fault normalizes to the same exceptional projection.
    of TransferStop.OutOfGas:
      instructions.add(registerImmediate(7, high(uint64)))
      instructions.add(registerImmediate(11, 100000))
      instructions.add(@[10'u8, 22]) # Valid offered gas cannot be funded by the remaining initial allowance.
    of TransferStop.HashReturn:
      instructions.add(registerImmediate(7, 65536))
      instructions.add(registerImmediate(8, 32)) # Readable hash return preserves every regular transfer.
  instructions.add(@[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memo):
    result.add(octet) # Canonical empty metadata frame precedes the full guest envelope in the account preimage.

proc queued(base: OwnedReport, id: byte, gas: uint64): ReadyItem =
  ## A real parent-ready report for destination 99 shares its recursive service with incoming transfers.
  let raw = reportBytes(reportFor(base, 0, [gas], service = 99))
  var report = decodeReportBorrowed(raw, 2).value
  report.header.packageHash.bytes[0] = id
  var bytes = newSeq[byte](raw.len+10000)
  let written = encodeReportBorrowed(report, raw, 2, bytes)
  assert written.error == CompositeError.None
  ReadyItem(report: decodeOwnedReport(bytes.toOpenArray(0, written.written-1), 2).value,
      dependencies: @[])

proc fixture(base: OwnedReport, reports: ReadyRow = @[], stop = TransferStop.Halt,
    checkpoint = true, zeroGas = false, missing = false, budget = 200000'u64): ExecutionFixture =
  ## Sign the actual complete parent with both programs, a funded sender and an uninvoked destination account.
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = (if missing: ExecutionEnding.Missing else: ExecutionEnding.Halt)
  executionOptions0.firstProgram = code(true, stop, checkpoint, zeroGas)
  executionOptions0.secondProgram = code(false, zeroGas = zeroGas)
  executionOptions0.signed.ready = reports
  executionOptions0.secondBalance = 20
  executionOptions0.signed.extra = @[serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(
      balance: AccountBalance(10)), ByteLimit(ServiceMetadataBytes)).value]
  result = executionFixture(base, executionOptions0)
  var config = executionRoundConfig()
  config.blockGas = Gas(budget)
  result.round = planBlockInitialAccumulation(result.round.roundBlockQueue.value, config).value

proc guest(source: ExecutionFixture, index: uint64): AccumulationDispatchResult =
  ## Execute the authenticated initial service with explicit finite transfer capture and host-work policies.
  executionGuest(source, index, parameters = profile(), copyLimit = MemoryByteLimit(128),
    transferLimit = ElementLimit(3), steps = ExecutionStepLimit(100), calls = HostCallLimit(10))

proc complete(source: ExecutionFixture, reverse = false): CompletedBlockAccumulation =
  ## Complete actual full common-source coverage while allowing execution order to differ from numeric service order.
  let first = guest(source, 0)
  let second = guest(source, 1)
  assert first.error == AccumulationDispatchError.None and second.error ==
      AccumulationDispatchError.None
  let executions = (if reverse: [second, first] else: [first, second])
  completeBlockAccumulation(source.round, executions, [], executionLimits()).value

proc limits(executions = 2'u64, transfers = 3'u64,
    memoBytes = 384'u64): AccumulationContinuationLimits =
  ## Independent finite caps include rejected report/digest inspections and every duplicate memo.
  AccumulationContinuationLimits(executions: ElementLimit(executions), transfers: ElementLimit(
      transfers),
    memoBytes: ByteLimit(memoBytes), reports: ElementLimit(2), digests: ElementLimit(2))

proc inputConfig(): AccumulationContinuationInputConfig =
  ## Existing bounded report ranges combine with transferred destination groups and no recurring allowances.
  AccumulationContinuationInputConfig(operands: executionRoundConfig().operands,
      inputs: executionRoundConfig().inputs)

proc balance(state: StateStoreSnapshot, service: uint32): uint64 =
  ## Inspect the actual complete map's canonical balance rather than trusting copied grouping facts.
  uint64(decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      service))).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata.balance)

proc checkTransferContinuation*(base: OwnedReport) =
  ## Run bound transfer/gas/input witnesses once per native suite and release all signed fixtures before returning.
  let reports = @[queued(base, 91, 10), queued(base, 92, 200000), queued(base, 93, 0)]
  let source = fixture(base, reports)
  let completed = complete(source, reverse = true)
  assert uint64(completed.executionInfo.value.round.prefix) == 0
  failHash(1)
  let plan = planAccumulationContinuation(completed, limits()).value
  let info = plan.continuationInfo.value
  assert info.transfers == 3 and uint64(info.transferGas) == 13
  assert uint64(info.prefix) == 1 and uint64(info.reportGas) == 10 and info.dispatch
  assert uint64(info.budget) == 200000-uint64(completed.executionInfo.value.gasUsed)+13
  let bound = plan.continuationTransfers.value
  let collection = bound.roundTransferCollection.value
  assert collection.transferCollectionInfo.value.sources == 2 and uint64(
      bound.roundTransferInfo.value.gas) == 13
  for index, service in [42'u32, 42'u32, 99'u32]:
    let transfer = collection.collectedTransferAt(CollectedTransferIndex(uint64(index))).value
    assert uint32(transfer.source) == service, "canonical source order is independent of execution array order"
    assert uint32(transfer.destination) == (if index < 2: 99'u32 else: 77'u32)
    assert uint64(transfer.amount) == (if index < 2: 0'u64 else: 5'u64)
    assert uint64(transfer.gas) == (if index < 2: 3'u64 else: 7'u64)
    let bytes = array[128, byte](transfer.memo)
    for offset in 0..<128:
      assert bytes[offset] == byte((offset*7+(if index < 2: 3 else: 11)) mod 256)
  assert hashCalls() == 0, "canonical collection, gas restoration and report selection are hash-free"
  for limited in [limits(executions = 1), limits(transfers = 2), limits(memoBytes = 383), limits(
      transfers = 0)]:
    assert planAccumulationContinuation(completed, limited).error ==
        AccumulationContinuationError.LimitExceeded
  let absent = default(PreparedRoundAccumulationTransfers)
  assert absent.roundTransferInfo.error == AccumulationRoundTransferError.Uninitialized
  assert absent.roundTransferSource.error == AccumulationRoundTransferError.Uninitialized
  assert absent.roundTransferCollection.error == AccumulationRoundTransferError.Uninitialized
  let invalid = default(CompletedBlockAccumulation)
  assert prepareRoundAccumulationTransfers(invalid, AccumulationTransferCollectionLimits()).error ==
      AccumulationRoundTransferError.InvalidSource
  let absentContinuation = default(PreparedAccumulationContinuation)
  assert absentContinuation.continuationTransfers.error ==
      AccumulationContinuationError.Uninitialized
  failHash(0)
  let owner = prepareAccumulationContinuationInputs(plan, inputConfig()).value
  let inputs = owner.continuationInputs.value
  assert inputs.invocationServiceCount.value == 2, "initial allowance-only sender 42 does not recur"
  let destination = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert uint32(destination.service) == 77 and destination.transfers == 1 and
      destination.operands == 0 and uint64(destination.gas) == 7
  let mixed = inputs.invocationServiceAt(InvocationServiceIndex(1)).value
  assert uint32(mixed.service) == 99 and mixed.transfers == 2 and mixed.operands == 1 and uint64(
      mixed.gas) == 16
  for index in 0..<2:
    assert inputs.invocationInputAt(InvocationServiceIndex(1), InvocationInputIndex(uint64(
        index))).value.kind == AccumulationKind.Transfer
  assert inputs.invocationInputAt(InvocationServiceIndex(1), InvocationInputIndex(2)).value.kind ==
      AccumulationKind.Operand
  assert balance(owner.continuationState.value, 99) == 15 and balance(owner.continuationState.value,
      77) == 10
  let credited = prepareContinuationAccumulationService(owner, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  assert balance(credited.serviceState.value, 77) == 15, "credit belongs to preparation from the real post-debit map"
  assert balance(owner.continuationState.value, 77) == 10 and balance(source.state.snapshot.value,
      99) == 20
  let supplied = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(
      0)).value.transfer
  assert uint32(supplied.source) == 99 and uint64(supplied.amount) == 5
  var limitedConfig = inputConfig()
  limitedConfig.inputs.inputs = ElementLimit(2)
  failHash(1)
  let limited = prepareAccumulationContinuationInputs(plan, limitedConfig)
  assert limited.error == AccumulationContinuationInputError.InputFailure and limited.inputError ==
      AccumulationInputError.LimitExceeded
  for cap in [0, 1]:
    var combined = inputConfig()
    if cap == 0:
      combined.inputs.inputs = ElementLimit(3) # Three transfers fit alone; the selected operand must still consume one input.
    else:
      combined.inputs.services = ElementLimit(1) # Report service 99 alone fits; transferred service 77 adds a distinct group.
    let short = prepareAccumulationContinuationInputs(plan, combined)
    assert short.error == AccumulationContinuationInputError.InputFailure and short.inputError ==
        AccumulationInputError.LimitExceeded
  assert hashCalls() == 0, "combined input and late destination-group limits refuse before state hashing"
  let refused = prepareAccumulationContinuationInputs(plan, inputConfig())
  assert refused.error == AccumulationContinuationInputError.BatchFailure
  assert refused.batchFailure.storeError == StateStoreError.BackendFailure
  failHash(0)
  assert balance(source.state.snapshot.value, 99) == 20, "refused private application leaves the exact prior unmodified"
  for stop in [TransferStop.Halt, TransferStop.HashReturn, TransferStop.Panic, TransferStop.Fault,
      TransferStop.OutOfGas]:
    for checkpoint in [false, true]:
      let local = fixture(base, stop = stop, checkpoint = checkpoint)
      let done = complete(local)
      let selected = planAccumulationContinuation(done, limits()).value
      let normal = stop in {TransferStop.Halt, TransferStop.HashReturn}
      let first = (if normal: 2 else: (if checkpoint: 1 else: 0))
      assert selected.continuationInfo.value.transfers == first+1
      assert uint64(selected.continuationInfo.value.transferGas) == uint64(first)*3+7
      assert uint64(selected.continuationInfo.value.prefix) == 0 and
          selected.continuationInfo.value.dispatch
  let zeros = complete(fixture(base, zeroGas = true))
  let zeroInfo = planAccumulationContinuation(zeros, limits()).value.continuationInfo.value
  assert zeroInfo.transfers == 3 and uint64(zeroInfo.transferGas) == 0 and uint64(
      zeroInfo.prefix) == 0 and zeroInfo.dispatch
  let maximum = complete(fixture(base, budget = high(uint64)))
  let maximumInfo = planAccumulationContinuation(maximum, limits()).value.continuationInfo.value
  assert uint64(maximumInfo.budget) == high(uint64)-(uint64(maximum.executionInfo.value.gasUsed)-13)
  let skipped = fixture(base, missing = true)
  let skippedDone = completeBlockAccumulation(skipped.round, [guest(skipped, 1)], [executionSkip(
      skipped, 0)], executionLimits()).value
  let skippedInfo = planAccumulationContinuation(skippedDone, limits(
      executions = 1)).value.continuationInfo.value
  assert skippedInfo.transfers == 1 and uint64(skippedInfo.transferGas) == 7
  var observed = bound.roundTransferInfo.value
  observed.gas = Gas(0)
  observed.collection.transfers = 0
  assert uint64(bound.roundTransferInfo.value.gas) == 13 and
      bound.roundTransferInfo.value.collection.transfers == 3
  assert sameAccumulationInputs(bound.roundTransferSource.value.executionRound.value.roundProjection.value.roundInputs.value,
    completed.executionRound.value.roundProjection.value.roundInputs.value), "bound source retains the exact completed input owner"
  var copied = info
  copied.budget = Gas(0)
  copied.transfers = 0
  assert plan.continuationInfo.value.transfers == 3 and uint64(plan.continuationInfo.value.budget) > 0
  var detached = default(PreparedRoundAccumulationTransfers)
  block released_callers:
    let local = complete(fixture(base))
    detached = planAccumulationContinuation(local, limits()).value.continuationTransfers.value
  assert detached.roundTransferCollection.value.transferCollectionInfo.value.transfers == 3
  assert detached.roundTransferSource.value.executionInfo.value.batch.completeInputs
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let selected = planAccumulationContinuation(completed, limits()).value
    let prepared = prepareAccumulationContinuationInputs(selected, inputConfig()).value
    assert balance(prepared.continuationState.value, 99) == 15
    assert prepared.continuationInputs.value.invocationServiceCount.value == 2
  let after = getOccupiedMem()
  assert before == after, "transfer continuation owners, memos, private debit maps and grouped inputs release across 1000 cycles"
