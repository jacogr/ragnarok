# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_reentry_arc_release"}

## Genuine later-round gas releases only the next original-queue range; its actual batch supplies the full successor.

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/reentry as accumulation_reentry
import ../../../src/state/accumulation/continuation/[
    execution as accumulation_continuation_execution, inputs as accumulation_continuation_inputs]
import ../../../src/state/accumulation/[continuation as accumulation_continuation,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue,
    operands as accumulation_operands, inputs as accumulation_inputs, batch as accumulation_batch,
    provisions as accumulation_provisions, service as accumulation_service]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite, report_owned]
import ../../../src/codec/work/[report as work_report, digest as work_digest]
import ../../../src/codec/state/[workqueues as state_workqueues, layout as state_layout,
    service_values as state_service_values, trie as state_trie]
import ../../../src/codec/c2_records
import ../../../src/crypto/primitives
import ../../support/[accumulation_continuation_execution_context, accumulation_execution_context,
  accumulation_batch_context, pvm_accumulation_provision, report_context, arc_evidence]

# Refuse the maintained test hash provider only after genuine signing/execution setup.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type
  Fixture = object # Original full rows and certified later completion permit independent successor assertions.
    initial: ExecutionFixture
    completed: CompletedAccumulationContinuation

# Unique package identities and explicit service 99 survive real parent signing/admission.
proc ready(base: OwnedReport, id: byte, gases: openArray[uint64],
    firstService = 42'u32): ReadyItem =
  let raw = reportBytes(reportFor(base, 0, gases, service = firstService))
  var report = decodeReportBorrowed(raw, 2).value
  report.header.packageHash.bytes[0] = id
  if gases.len == 2: report.digests[1].service = ServiceIndex(99) # Match the two authenticated accounts.
  var bytes = newSeq[byte](raw.len+10000)
  let written = encodeReportBorrowed(report, raw, 2, bytes)
  assert written.error == CompositeError.None
  ReadyItem(report: decodeOwnedReport(bytes.toOpenArray(0, written.written-1), 2).value,
      dependencies: @[])

# Reserve the complete initial budget, then almost the entire first continuation budget, forcing a real next suffix.
proc fixture(base: OwnedReport, provided = false, blocked = false, stopped = false,
    mathematical = false): Fixture =
  let second = if stopped: @[high(uint64)] else:
    @[if provided: 50000'u64 else: 100000'u64, if provided: 50000'u64 else: 100000'u64]
  let following = if mathematical: @[5'u64, high(uint64)] elif blocked: @[high(uint64)] else: @[1000'u64]
  let queue = @[ready(base, 64, [1000'u64], if provided: 99'u32 else: 42'u32),
    ready(base, 65, second), ready(base, 66, following), ready(base, 67, [0'u64])]
  var code: seq[byte] = @[]
  var extra: seq[StateEntry] = @[]
  if provided:
    code.add(0)
    for octet in batchEnvelope(BatchEnding.Halt): code.add(
        octet) # First initial invocation has only one gas and cannot provide yet.
    extra = @[provisionRequest(42, @[73'u8]), provisionRequest(99, @[81'u8])]
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.signed.ready = queue
  executionOptions0.firstProgram = code
  executionOptions0.signed.extra = extra
  executionOptions0.first = (if provided: ExecutionEnding.Exhausted else: ExecutionEnding.Halt)
  var initial = executionFixture(base, executionOptions0)
  var config = executionRoundConfig()
  config.blockGas = Gas(if provided: 101001'u64 else: 201000'u64)
  initial.round = planBlockInitialAccumulation(initial.round.roundBlockQueue.value, config).value
  let completed = completeBlockAccumulation(initial.round,
    [executionGuest(initial, 0), executionGuest(initial, 1)], [], executionLimits()).value
  let plan = planAccumulationContinuation(completed,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(4),
        digests: ElementLimit(8))).value
  let source = prepareAccumulationContinuationInputs(plan,
    AccumulationContinuationInputConfig(operands: config.operands, inputs: config.inputs)).value
  if stopped:
    return Fixture(initial: initial, completed: completeAccumulationContinuation(source, [], [],
        executionLimits()).value) # A real n=0 source cannot restart.
  let first = if provided:
    continuationGuest(source, 0, provisionPolicy(items = 2, perBlob = 1, total = 2))
  else: continuationGuest(source, 0) # Actual regular halt has no provisions.
  Fixture(initial: initial, completed: completeAccumulationContinuation(source,
    [first, continuationGuest(source, 1)], [], executionLimits()).value)

proc config(): AccumulationReentryConfig =
  # Selection work includes the zero-cost tail; independent input ceilings apply only to selected reports.
  AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(2),
    reports: ElementLimit(2), digests: ElementLimit(2)), operands: executionRoundConfig().operands,
    inputs: executionRoundConfig().inputs)

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index]) # Preserve the checksum-verified binary witness.
  let base = decodeOwnedReport(bytes, 2).value
  let ordinary = fixture(base)
  failHash(3)
  let next = prepareAccumulationReentry(ordinary.completed, config()).value
  let info = next.reentryInfo.value
  assert uint64(info.completedPrefix) == 2 and uint64(info.prefix) == 2 and info.pendingReports == 2
  assert uint64(info.budget) == 200912 and uint64(info.reportGas) == 1000 and info.dispatch
  let inputs = next.reentryInputs.value
  assert inputs.invocationServiceCount.value == 1 # Allowance-only service 99 does not recur.
  let operands = inputs.invocationOperands.value
  assert uint64(operands.operandReportStart.value) == 2 and uint64(
      operands.operandReportPrefix.value) == 2
  for index, id in [66'u8, 67]:
    assert ownedReportInfo(next.reentryReportAt(ContinuationReportIndex(uint64(
        index))).value).value.header.packageHash.bytes[0] == id
    let operand = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(uint64(
        index))).value.operand
    assert operand.operandInfo.value.packageHash.bytes[0] == id
  let group = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert uint64(group.gas) == 1000 and group.operands == 2 and group.transfers == 0
  assert sameStateSnapshot(next.reentryState.value, ordinary.initial.state.snapshot.value)
  assert uint64(next.reentrySource.value.executionInfo.value.gasUsed) == 44
  assert next.reentryReportAt(ContinuationReportIndex(high(uint64))).error ==
      AccumulationReentryError.InvalidIndex
  var copied = info
  copied.budget = Gas(1)
  assert uint64(next.reentryInfo.value.budget) == 200912
  var limited = config()
  limited.selection.executions = ElementLimit(1)
  assert prepareAccumulationReentry(ordinary.completed, limited).error ==
      AccumulationReentryError.LimitExceeded
  limited = config()
  limited.selection.reports = ElementLimit(1)
  assert prepareAccumulationReentry(ordinary.completed, limited).error ==
      AccumulationReentryError.LimitExceeded
  limited = config()
  limited.selection.digests = ElementLimit(1)
  assert prepareAccumulationReentry(ordinary.completed, limited).error ==
      AccumulationReentryError.LimitExceeded
  limited = config()
  limited.operands.reports = ElementLimit(1)
  assert prepareAccumulationReentry(ordinary.completed, limited).operandError ==
      AccumulationOperandError.LimitExceeded
  limited = config()
  limited.inputs.services = ElementLimit(0)
  assert prepareAccumulationReentry(ordinary.completed, limited).inputError ==
      AccumulationInputError.LimitExceeded
  let empty = default(PreparedAccumulationReentry)
  assert empty.reentryInfo.error == AccumulationReentryError.Uninitialized
  assert empty.reentrySource.error == AccumulationReentryError.Uninitialized
  assert empty.reentryInputs.error == AccumulationReentryError.Uninitialized
  assert empty.reentryState.error == AccumulationReentryError.Uninitialized
  assert empty.reentryReportAt(ContinuationReportIndex(0)).error ==
      AccumulationReentryError.Uninitialized
  assert prepareAccumulationReentry(default(CompletedAccumulationContinuation), config()).error ==
      AccumulationReentryError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  let service = prepareReentryAccumulationService(next, InvocationServiceIndex(0),
      continuationServiceConfig()).value
  assert serviceSourceMatches(service, inputs, next.reentryState.value)
  assert uint32(service.serviceInfo.value.slot) == 2
  assert prepareReentryAccumulationService(next, InvocationServiceIndex(high(uint64)),
      continuationServiceConfig()).serviceError == AccumulationServiceError.InvalidIndex
  assert prepareReentryAccumulationService(empty, InvocationServiceIndex(0),
      continuationServiceConfig()).error == AccumulationReentryError.Uninitialized
  let blocked = fixture(base, blocked = true)
  let math = fixture(base, mathematical = true)
  let stopped = fixture(base, stopped = true)
  let emptyFixture = continuationExecutionFixture(base, empty = true)
  let emptyCompletion = completeAccumulationContinuation(emptyFixture.source, [], [],
      executionLimits(0)).value
  let allSkip = continuationExecutionFixture(base, first = ExecutionEnding.Missing,
    second = ExecutionEnding.Missing)
  let skipCompletion = completeAccumulationContinuation(allSkip.source, [],
    [continuationSkip(allSkip.source, 0), continuationSkip(allSkip.source, 1)], executionLimits()).value
  failHash(3)
  var noWork = config()
  noWork.selection = default(AccumulationContinuationLimits)
  let skipPlan = prepareAccumulationReentry(skipCompletion, noWork).value
  assert uint64(skipPlan.reentryInfo.value.budget) == 201000
  assert uint64(skipPlan.reentryInfo.value.completedPrefix) == 2
  assert skipPlan.reentryInfo.value.pendingReports == 0
  for source in [blocked.completed, math.completed]:
    let plan = prepareAccumulationReentry(source, config()).value
    assert uint64(plan.reentryInfo.value.prefix) == 0 and
        not plan.reentryInfo.value.dispatch # No bypass or partially committed digest reservation.
  limited = config()
  limited.selection = default(AccumulationContinuationLimits)
  let stoppedPlan = prepareAccumulationReentry(stopped.completed, limited).value
  assert uint64(stoppedPlan.reentryInfo.value.completedPrefix) == 1
  assert stoppedPlan.reentryInfo.value.pendingReports == 3 and
      not stoppedPlan.reentryInfo.value.dispatch
  assert prepareAccumulationReentry(emptyCompletion,
      limited).value.reentryInputs.value.invocationServiceCount.value == 0
  assert hashCalls() == 0
  failHash(0)
  # Initial OOG left requests outstanding; only the actual completed later batch can fulfill them now.
  let provided = fixture(base, provided = true)
  let prior = provided.completed.executionContinuation.value.continuationState.value
  var rows: seq[StateEntry] = @[]
  for row in provided.initial.entries: rows.add(StateEntry(key: row.key, value: row.value))
  for ordinal, id in [42'u32, 99]:
    let payload = if ordinal == 0: @[73'u8] else: @[81'u8]
    let request = provisionRequest(id, payload)
    for index in 0..<rows.len:
      if array[31, byte](rows[index].key) == array[31, byte](request.key):
        rows[index].value = @[1'u8, 2, 0, 0, 0] # Independent literal fulfillment at authenticated slot 2.
    rows.add(servicePreimageEntry(ServiceIndex(id), ServicePreimageHash(array[32, byte](blake2b256(
        payload).value)),
      payload, ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)
  let expected = newStateStore(rows, report_context.limits()).value.snapshot.value
  failHash(1)
  let refused = prepareAccumulationReentry(provided.completed, config())
  assert refused.batchFailure.provisionError == AccumulationProvisionError.BackendFailure
  assert sameStateSnapshot(provided.initial.state.snapshot.value, prior)
  failHash(0)
  let posterior = prepareAccumulationReentry(provided.completed, config()).value
  assert array[32, byte](posterior.reentryState.value.commitment.root) == array[32, byte](
      expected.commitment.root)
  assert prior.lookup(provisionRequest(42, @[73'u8]).key).value.bytes == @[0'u8]
  assert posterior.reentryState.value.lookup(provisionRequest(42, @[73'u8]).key).value.bytes == @[
      1'u8, 2, 0, 0, 0]
  let successorService = prepareReentryAccumulationService(posterior, InvocationServiceIndex(0),
      continuationServiceConfig()).value
  assert serviceSourceMatches(successorService, posterior.reentryInputs.value,
      posterior.reentryState.value)
  assert not serviceSourceMatches(successorService, posterior.reentryInputs.value, prior)
  var retained: PreparedAccumulationReentry
  block:
    let local = fixture(base)
    retained = prepareAccumulationReentry(local.completed, config()).value
  assert uint64(retained.reentryInfo.value.completedPrefix) == 2
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    failHash(1)
    let refusal = prepareAccumulationReentry(provided.completed, config())
    assert refusal.batchFailure.provisionError == AccumulationProvisionError.BackendFailure
    failHash(0)
    let success = prepareAccumulationReentry(provided.completed, config()).value
    assert array[32, byte](success.reentryState.value.commitment.root) == array[32, byte](
        expected.commitment.root)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_reentry", 1000, before, after)
  echo "Accumulation reentry selection and state passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Missing fixtures and unexpected exceptions remain native failures.
except:
  quit(2)
