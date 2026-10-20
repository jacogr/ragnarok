# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed four-report reentry fixtures retain actual completed prior rounds and immutable full-map provenance.

import std/assertions
import ../../src/state/[accumulation_reentry, accumulation_reentry_invocation,
  accumulation_continuation_execution, accumulation_continuation_inputs, accumulation_continuation,
  accumulation_execution, accumulation_round, accumulation_inputs, accumulation_service,
  accumulation_invocation, accumulation_dispatch, accumulation_skip, accumulation_effects,
  accumulation_machine, store]
import ../../src/codec/[bounded, composite, report_owned, work_report, work_digest,
  state_workqueues, state_history, state_layout, state_trie, c2_records]
import ../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ./[accumulation_execution_context, accumulation_continuation_execution_context,
  accumulation_batch_context, pvm_accumulation_provision, pvm_accumulation_context, report_context]

type
  ReentryFixture* = object ## Original authored rows remain available for independent foreign-map and state-change tests.
    initial*: ExecutionFixture ## Genuine initial round and original complete state.
    source*: PreparedAccumulationReentry ## Selected reentry after actual completed initial and later rounds.

proc reentryReady*(base: OwnedReport, id: byte, gases: openArray[uint64],
    firstService = 42'u32): ReadyItem =
  ## Capture a uniquely identified ready report before real parent signing; optional second digest targets service 99.
  let raw = reportBytes(reportFor(base, 0, gases, service = firstService))
  var decoded = decodeReportBorrowed(raw, 2).value
  decoded.header.packageHash.bytes[0] = id
  if gases.len == 2: decoded.digests[1].service = ServiceIndex(99) # Match the second authenticated account.
  var bytes = newSeq[byte](raw.len+10000)
  let written = encodeReportBorrowed(decoded, raw, 2, bytes)
  assert written.error == CompositeError.None
  ReadyItem(report: decodeOwnedReport(bytes.toOpenArray(0, written.written-1), 2).value,
      dependencies: @[])

proc reentryFixture*(base: OwnedReport, first = ExecutionEnding.Halt, second = ExecutionEnding.Halt,
    firstGas = 1000'u64, secondGas = 1000'u64, provided = false, stopped = false,
    empty = false, tail: ReadyRow = @[], firstProgram: seq[byte] = @[],
    secondProgram: seq[byte] = @[], extra: seq[StateEntry] = @[], incomingReports = 0,
    preimageWire: seq[byte] = @[], historyPeaks: seq[HistoryPeak] = @[]): ReentryFixture =
  ## Consume one report initially, reserve nearly all later gas in the second, then release the true two-service reentry suffix.
  # Optional code preimages and belt peaks enter the parent; incoming reports/preimage wire enter the signed child; provided retains its guest.
  let firstEnding = if provided: ExecutionEnding.Exhausted else: first
  var budget = 1000'u64
  for ending in [firstEnding, second]:
    let allowance = if ending == ExecutionEnding.Exhausted: 1'u64 elif ending ==
        ExecutionEnding.HostExhausted: 200'u64 else: 100000'u64
    budget += allowance # Two finite fixture credits and the first report fit independently of supplied reentry gas.
  let reserved = if budget < 200000: 100000'u64 else: 200000'u64
  let middle = if stopped: @[high(uint64)] else: @[reserved div 2, reserved div 2]
  var queue = if empty: newSeq[ReadyItem]() else:
    @[reentryReady(base, 64, [1000'u64], if provided: 99'u32 else: 42'u32), reentryReady(base, 65,
        middle),
      reentryReady(base, 66, [firstGas, secondGas]), reentryReady(base, 67, [0'u64])]
  for item in tail: queue.add(item) # Additional authenticated suffix rows permit real repeated-round witnesses.
  var code = firstProgram
  var entries = extra # Additional authored state enters the signed parent, never an existing certificate.
  if provided:
    code = @[0'u8]
    for octet in batchEnvelope(BatchEnding.Halt): code.add(
        octet) # Initial one-gas OOG cannot reach provide; later execution can.
    entries.add(provisionRequest(42, @[73'u8]))
    entries.add(provisionRequest(99, @[81'u8]))
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = firstEnding
  executionOptions0.second = second
  executionOptions0.empty = empty
  executionOptions0.signed.ready = queue
  executionOptions0.firstProgram = code
  executionOptions0.secondProgram = secondProgram
  executionOptions0.signed.extra = entries
  executionOptions0.signed.reports = incomingReports
  executionOptions0.signed.preimageWire = preimageWire
  executionOptions0.signed.historyPeaks = historyPeaks
  var initial = executionFixture(base, executionOptions0)
  var policy = executionRoundConfig()
  policy.blockGas = Gas(budget)
  initial.round = planBlockInitialAccumulation(initial.round.roundBlockQueue.value, policy).value
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  if not empty:
    for index, ending in [firstEnding, second]:
      if ending == ExecutionEnding.Missing: skips.add(executionSkip(initial, uint64(
          index))) # Only certified missing code may skip.
      else: runs.add(executionGuest(initial, uint64(index))) # Preserve real PVM gas and terminal outcomes.
  let completed = completeBlockAccumulation(initial.round, runs, skips, executionLimits()).value
  let plan = planAccumulationContinuation(completed,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(4),
        digests: ElementLimit(8))).value
  let context = prepareAccumulationContinuationInputs(plan,
    AccumulationContinuationInputConfig(operands: policy.operands, inputs: policy.inputs)).value
  runs.setLen(0)
  skips.setLen(0)
  if context.continuationPlan.value.continuationInfo.value.dispatch:
    for index, ending in [firstEnding, second]:
      if ending == ExecutionEnding.Missing: skips.add(continuationSkip(context, uint64(index)))
      elif provided and index == 0:
        runs.add(continuationGuest(context, uint64(index), provisionPolicy(items = 2, perBlob = 1,
            total = 2))) # Actual later provisions change reentry's full map.
      else: runs.add(continuationGuest(context, uint64(index))) # Actual later usage replaces reservations.
  let later = completeAccumulationContinuation(context, runs, skips, executionLimits()).value
  ReentryFixture(initial: initial, source: prepareAccumulationReentry(later,
    AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(2),
      reports: ElementLimit(4), digests: ElementLimit(8)), operands: policy.operands,
          inputs: policy.inputs)).value)

proc reentryRun*(invocation: PreparedAccumulationInvocation,
    provisions = default(AccumulationProvisionLimits)): AccumulationDispatchResult =
  ## Capture both selected service-42 operands, then execute only the supplied immutable bootstrap.
  let machine = initializeAccumulationMachine(invocation, InitializationLimits(
    envelope: InitializationByteLimit(512), program: ProgramByteLimit(256), jumps: JumpCountLimit(0),
    pages: PageLimit(5))).value
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  executeAccumulationMachine(machine, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(2), bytes: ByteLimit(1024),
      operand: OperandLimits(maxBytes: ByteLimit(512))), MemoryByteLimit(32),
    ExecutionStepLimit(40), HostCallLimit(8), GasCycleLimit(1000), contexts, provisions)

proc reentryGuest*(source: PreparedAccumulationReentry, index: uint64,
    provided = false): AccumulationDispatchResult =
  ## Run only the source-derived bootstrap through existing bounded machine/dispatch adapters.
  let bound = prepareReentryAccumulationInvocation(source, InvocationServiceIndex(index),
    continuationServiceConfig(), ServiceProbeLimit(1)).value.bootstrapProjection.value
  if provided:
    return reentryRun(bound, provisionPolicy(items = 2, perBlob = 1,
        total = 2)) # Finite capture policy for real provides.
  reentryRun(bound)

proc reentrySkip*(source: PreparedAccumulationReentry, index: uint64): SkippedAccumulation =
  ## Certify only the real reentry service's non-invoking code alternative.
  finishUninvokedAccumulation(prepareReentryAccumulationService(source, InvocationServiceIndex(index),
    continuationServiceConfig()).value).value
