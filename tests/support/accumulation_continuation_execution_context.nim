# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed completed initial rounds and actual later-round dispatches for continuation coverage tests.

import std/assertions
import ../../src/state/[accumulation_continuation_inputs, accumulation_continuation,
  accumulation_continuation_invocation, accumulation_execution, accumulation_round,
  accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_machine,
  accumulation_dispatch, accumulation_skip, accumulation_effects, store]
import ../../src/codec/[bounded, composite, header, report_owned, work_report, work_digest,
  state_workqueues, c2_records]
import ../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ./[accumulation_execution_context, report_context, pvm_accumulation_context,
    accumulation_batch_context, pvm_accumulation_provision]

type
  ContinuationExecutionFixture* = object ## Original signed map and exact later-round context remain separately observable.
    initial*: ExecutionFixture ## Genuine initial round, original complete map and authored rows.
    source*: PreparedAccumulationContinuationInputs ## Only the selected suffix feeds later invocations.

# Re-encode a unique ready report with service 99 as the optional second digest rather than service 43.
proc report(base: OwnedReport, id: byte, gases: openArray[uint64]): ReadyItem =
  let raw = reportBytes(reportFor(base, 0, gases))
  var decoded = decodeReportBorrowed(raw, 2).value
  decoded.header.packageHash.bytes[0] = id
  if gases.len == 2:
    decoded.digests[1].service = ServiceIndex(99) # The two authenticated services have independent selected gas.
  var bytes = newSeq[byte](raw.len+10000)
  let written = encodeReportBorrowed(decoded, raw, 2, bytes)
  assert written.error == CompositeError.None
  ReadyItem(report: decodeOwnedReport(bytes.toOpenArray(0, written.written-1), 2).value,
      dependencies: @[])

proc continuationExecutionFixture*(base: OwnedReport, first = ExecutionEnding.Halt,
    second = ExecutionEnding.Halt, firstGas = 300'u64, secondGas = 300'u64,
    empty = false): ContinuationExecutionFixture =
  ## Consume the first report in the initial round; only actual unused gas admits the two-service suffix.
  let ready = if empty: newSeq[ReadyItem]() else:
    @[report(base, 64, [1000'u64]), report(base, 65, [firstGas, secondGas])]
  var initial = executionFixture(base, first = first, second = second, ready = ready, empty = empty)
  var policy = executionRoundConfig()
  var budget = 1000'u64
  for ending in [first, second]:
    let allowance = if ending == ExecutionEnding.Exhausted: 1'u64 elif ending ==
        ExecutionEnding.HostExhausted: 200'u64 else: 100000'u64
    budget += allowance # Two fixed test credits and one tiny report fit uint64 independently of supplied report gas.
  policy.blockGas = Gas(budget)
  initial.round = planBlockInitialAccumulation(initial.round.roundBlockQueue.value, policy).value
  var executions: seq[AccumulationDispatchResult] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  if not empty:
    for index, ending in [first, second]:
      if ending == ExecutionEnding.Missing:
        skipped.add(executionSkip(initial, uint64(
            index))) # Only genuine missing code authorizes a non-executing outcome.
      else:
        executions.add(executionGuest(initial, uint64(index))) # CPU outcomes and gas are never forged.
  let completed = completeBlockAccumulation(initial.round, executions, skipped, executionLimits()).value
  let plan = planAccumulationContinuation(completed,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(2),
      digests: ElementLimit(2))).value
  ContinuationExecutionFixture(initial: initial, source: prepareAccumulationContinuationInputs(plan,
    AccumulationContinuationInputConfig(operands: policy.operands, inputs: policy.inputs)).value)

proc continuationServiceConfig*(): AccumulationServiceConfig =
  ## Keep complete preimage and executable budgets independent of gas and provenance.
  AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))

proc continuationRun*(invocation: PreparedAccumulationInvocation,
    provisions = default(AccumulationProvisionLimits)): AccumulationDispatchResult =
  ## Initialize and execute the exact supplied immutable bootstrap through existing bounded PVM adapters.
  let machine = initializeAccumulationMachine(invocation, InitializationLimits(
    envelope: InitializationByteLimit(512), program: ProgramByteLimit(256), jumps: JumpCountLimit(0),
    pages: PageLimit(5))).value
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  executeAccumulationMachine(machine, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(1), bytes: ByteLimit(512),
      operand: OperandLimits(maxBytes: ByteLimit(512))), MemoryByteLimit(32),
    ExecutionStepLimit(40), HostCallLimit(8), GasCycleLimit(1000), contexts, provisions)

proc continuationGuest*(source: PreparedAccumulationContinuationInputs,
    index: uint64, provisions = default(AccumulationProvisionLimits)): AccumulationDispatchResult =
  ## Derive service/slot/entropy only from the exact prepared continuation and authenticated block stage.
  continuationRun(prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(index),
    continuationServiceConfig(), ServiceProbeLimit(1)).value.bootstrapProjection.value, provisions)

proc continuationSkip*(source: PreparedAccumulationContinuationInputs,
    index: uint64): SkippedAccumulation =
  ## Certify missing-code service from this exact later-round input owner and actual posterior map.
  finishUninvokedAccumulation(prepareContinuationAccumulationService(source,
    InvocationServiceIndex(index), continuationServiceConfig()).value).value

proc continuationProvidedFixture*(base: OwnedReport): ContinuationExecutionFixture =
  ## Real initial provides fulfill outstanding requests before any later service or completion is prepared.
  var code = @[0'u8]
  for octet in batchEnvelope(BatchEnding.Halt): code.add(
      octet) # Preserve the complete code preimage metadata prefix.
  var initial = executionFixture(base, firstProgram = code,
    ready = @[report(base, 64, [1000'u64]), report(base, 65, [1000'u64, 1000])],
    extra = @[provisionRequest(42, @[73'u8]), provisionRequest(99, @[81'u8])])
  var policy = executionRoundConfig()
  policy.blockGas = Gas(201000)
  initial.round = planBlockInitialAccumulation(initial.round.roundBlockQueue.value, policy).value
  let service = prepareBlockAccumulationService(initial.round, InvocationServiceIndex(0),
    continuationServiceConfig()).value
  let invocation = prepareBlockAccumulationInvocation(service, ServiceProbeLimit(
      1)).value.bootstrapProjection.value
  let first = continuationRun(invocation, provisionPolicy(items = 2, perBlob = 1, total = 2))
  let complete = completeBlockAccumulation(initial.round,
    [first, executionGuest(initial, 1)], [], executionLimits()).value
  let plan = planAccumulationContinuation(complete,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(1),
        digests: ElementLimit(2))).value
  ContinuationExecutionFixture(initial: initial, source: prepareAccumulationContinuationInputs(plan,
    AccumulationContinuationInputConfig(operands: policy.operands, inputs: policy.inputs)).value)
