# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_continuation_inputs_arc_release"}

## Selected suffix operands retain original queue provenance and actual privately fulfilled state.

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/continuation/inputs as accumulation_continuation_inputs
import ../../../src/state/accumulation/[continuation as accumulation_continuation,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue,
    operands as accumulation_operands, inputs as accumulation_inputs, batch as accumulation_batch,
    service as accumulation_service, invocation as accumulation_invocation,
    machine as accumulation_machine, dispatch as accumulation_dispatch,
    provisions as accumulation_provisions]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite, report_owned, owned]
import ../../../src/codec/work/[report as work_report, digest as work_digest]
import ../../../src/codec/c2_records
import ../../../src/codec/state/[workqueues as state_workqueues, safrole as state_safrole,
    service_values as state_service_values, trie as state_trie, layout as state_layout]
import ../../../src/crypto/primitives
import ../../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ../../support/[accumulation_execution_context, accumulation_batch_context,
  pvm_accumulation_context, pvm_accumulation_provision, accumulation_provision_integration,
  report_context, accumulation_transfer_continuation, arc_evidence]

# Backend refusal distinguishes input preflight from private candidate-state fulfillment.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

# Capture distinguishable reports before they enter the genuinely signed parent ready ring.
proc queued(base: OwnedReport, id: byte, gas: uint64): ReadyItem =
  let raw = reportBytes(reportFor(base, 0, [gas]))
  var report = decodeReportBorrowed(raw, 2).value
  report.header.packageHash.bytes[0] = id
  var wire = newSeq[byte](raw.len+10000)
  let written = encodeReportBorrowed(report, raw, 2, wire)
  assert written.error == CompositeError.None
  ReadyItem(report: decodeOwnedReport(wire.toOpenArray(0, written.written-1), 2).value,
      dependencies: @[])

# Reuse independent operand/input ceilings without changing authenticated source or remaining gas.
proc config(): AccumulationContinuationInputConfig =
  AccumulationContinuationInputConfig(operands: executionRoundConfig().operands,
    inputs: executionRoundConfig().inputs)

# Execute actual provisions with bounded capture against the original signed source/entropy.
proc provided(fixture: ExecutionFixture): AccumulationDispatchResult =
  let service = prepareBlockAccumulationService(fixture.round, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  let invocation = prepareBlockAccumulationInvocation(service, ServiceProbeLimit(
      1)).value.bootstrapProjection.value
  let prepared = initializeAccumulationMachine(invocation, InitializationLimits(
    envelope: InitializationByteLimit(512), program: ProgramByteLimit(256), jumps: JumpCountLimit(
        0), pages: PageLimit(5))).value
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  executeAccumulationMachine(prepared, pvmParameters(), FetchAccumulationLimits(items: ElementLimit(1),
    bytes: ByteLimit(512), operand: OperandLimits(maxBytes: ByteLimit(512))), MemoryByteLimit(32),
    ExecutionStepLimit(40), HostCallLimit(8), GasCycleLimit(1000), contexts,
    provisionPolicy(items = 2, perBlob = 1, total = 2))

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  checkTransferContinuation(base) # Genuine transferred rounds exercise the new bound collection and input/gas path.
  let ready = @[queued(base, 64, 10), queued(base, 65, 11), queued(base, 66, 0)]
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = ExecutionEnding.Panic
  executionOptions0.second = ExecutionEnding.Panic
  executionOptions0.allowanceGas = 208
  executionOptions0.signed.ready = ready
  var fixture = executionFixture(base, executionOptions0)
  var roundConfig = executionRoundConfig()
  roundConfig.blockGas = Gas(426)
  fixture.round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value,
      roundConfig).value
  let completed = completeBlockAccumulation(fixture.round,
    [executionGuest(fixture, 0), executionGuest(fixture, 1)], [], executionLimits()).value
  let plan = planAccumulationContinuation(completed,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(2),
        digests: ElementLimit(2))).value
  assert uint64(plan.continuationInfo.value.completedPrefix) == 1
  failHash(3)
  let prepared = prepareAccumulationContinuationInputs(plan, config()).value
  let inputs = prepared.continuationInputs.value
  let operands = inputs.invocationOperands.value
  assert uint64(operands.operandReportStart.value) == 1
  assert uint64(operands.operandReportPrefix.value) == 2
  assert inputs.invocationServiceCount.value == 1 # Initial allowance-only service 99 does not recur.
  let group = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
  assert uint32(group.service) == 42 and uint64(group.gas) == 11
  assert group.operands == 2 and group.transfers == 0
  for index, id in [65'u8, 66]:
    let operand = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(uint64(
        index))).value.operand
    assert operand.operandInfo.value.packageHash.bytes[0] == id # Completed report 64 is not rematerialized.
  assert sameStateSnapshot(prepared.continuationState.value, fixture.state.snapshot.value)
  assert uint64(prepared.continuationPlan.value.continuationInfo.value.prefix) == 2
  let queue = fixture.round.roundBlockQueue.value.accumulationProjection.value
  let invalidStart = prepareAccumulationOperandRange(queue, AccumulationReportStart(high(uint64)),
      AccumulationReportPrefix(0), config().operands)
  assert invalidStart.error == AccumulationOperandError.InvalidPrefix
  assert prepareAccumulationOperandRange(queue, AccumulationReportStart(3),
      AccumulationReportPrefix(1), config().operands).error ==
      AccumulationOperandError.InvalidPrefix
  assert prepareAccumulationOperandRange(queue, AccumulationReportStart(1),
      AccumulationReportPrefix(high(uint64)), config().operands).error ==
      AccumulationOperandError.InvalidPrefix
  assert prepareAccumulationOperandRange(queue, AccumulationReportStart(3),
      AccumulationReportPrefix(0), config().operands).value.operandServiceCount.value == 0
  assert uint64(prepareAccumulationOperands(queue, AccumulationReportPrefix(1), config().operands).value.operandReportStart.value) == 0
  var limited = config()
  limited.operands.reports = ElementLimit(1)
  assert prepareAccumulationContinuationInputs(plan, limited).operandError ==
      AccumulationOperandError.LimitExceeded
  limited = config()
  limited.inputs.services = ElementLimit(0)
  assert prepareAccumulationContinuationInputs(plan, limited).inputError ==
      AccumulationInputError.LimitExceeded
  let defaultPlan = default(PreparedAccumulationContinuation)
  assert prepareAccumulationContinuationInputs(defaultPlan, config()).error ==
      AccumulationContinuationInputError.InvalidPlan
  let defaultOwner = default(PreparedAccumulationContinuationInputs)
  assert defaultOwner.continuationInputs.error == AccumulationContinuationInputError.Uninitialized
  assert defaultOwner.continuationState.error == AccumulationContinuationInputError.Uninitialized
  assert defaultOwner.continuationPlan.error == AccumulationContinuationInputError.Uninitialized
  let defaultOperands = default(PreparedAccumulationOperands)
  assert defaultOperands.operandReportStart.error == AccumulationOperandError.Uninitialized
  failHash(0)
  let service = prepareContinuationAccumulationService(prepared, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  assert serviceSourceMatches(service, inputs, prepared.continuationState.value)
  assert uint32(service.serviceInfo.value.slot) == 2 and uint64(service.serviceInfo.value.gas) == 11
  assert prepareContinuationAccumulationService(prepared, InvocationServiceIndex(high(uint64)),
    default(AccumulationServiceConfig)).serviceError == AccumulationServiceError.InvalidIndex
  assert prepareContinuationAccumulationService(defaultOwner, InvocationServiceIndex(0),
    default(AccumulationServiceConfig)).error == AccumulationContinuationInputError.Uninitialized
  # Initialized empty selections preserve exact no-op state while remaining distinct from defaults.
  var executionOptions1 = executionFixtureConfig()
  executionOptions1.empty = true
  let emptyFixture = executionFixture(base, executionOptions1)
  let emptySource = completeBlockAccumulation(emptyFixture.round, [], [], executionLimits(0)).value
  let emptyPlan = planAccumulationContinuation(emptySource, default(
      AccumulationContinuationLimits)).value
  failHash(3)
  let emptyOwner = prepareAccumulationContinuationInputs(emptyPlan, config()).value
  assert emptyOwner.continuationInputs.value.invocationServiceCount.value == 0
  assert sameStateSnapshot(emptyOwner.continuationState.value, emptyFixture.state.snapshot.value)
  failHash(0)
  # Actual terminal provides change the successor map even though its incoming continuation inputs remain report-only.
  var code = @[0'u8]
  for octet in batchEnvelope(BatchEnding.Halt): code.add(octet)
  var executionOptions2 = executionFixtureConfig()
  executionOptions2.signed.ready = @[ready[0]]
  executionOptions2.firstProgram = code
  executionOptions2.signed.extra = @[provisionRequest(42, @[73'u8]), provisionRequest(99, @[81'u8])]
  var effects = executionFixture(base, executionOptions2)
  var effectsConfig = executionRoundConfig()
  effectsConfig.blockGas = Gas(200000)
  effects.round = planBlockInitialAccumulation(effects.round.roundBlockQueue.value,
      effectsConfig).value
  let dispatched = provided(effects)
  assert dispatched.error == AccumulationDispatchError.None
  let appliedSource = completeBlockAccumulation(effects.round,
    [dispatched, executionGuest(effects, 1)], [], executionLimits()).value
  let effectPlan = planAccumulationContinuation(appliedSource,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(1),
        digests: ElementLimit(1))).value
  var rows: seq[StateEntry] = @[]
  for row in effects.entries: rows.add(StateEntry(key: row.key, value: row.value))
  for ordinal, id in [42'u32, 99]:
    let bytes = if ordinal == 0: @[73'u8] else: @[81'u8]
    let request = provisionRequest(id, bytes)
    for index in 0..<rows.len:
      if array[31, byte](rows[index].key) == array[31, byte](request.key):
        rows[index].value = @[1'u8, 2, 0, 0, 0] # Literal fulfillment at authenticated candidate slot 2.
    let preimage = servicePreimageEntry(ServiceIndex(id), ServicePreimageHash(array[32, byte](
        blake2b256(bytes).value)),
      bytes, ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value
    rows.add(preimage)
  let expected = newStateStore(rows, report_context.limits()).value.snapshot.value
  let original = effects.state.snapshot.value
  failHash(1)
  let refused = prepareAccumulationContinuationInputs(effectPlan, config())
  assert refused.batchFailure.provisionError == AccumulationProvisionError.BackendFailure
  assert sameStateSnapshot(effects.state.snapshot.value, original)
  failHash(0)
  let successor = prepareAccumulationContinuationInputs(effectPlan, config()).value
  let posterior = successor.continuationState.value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](expected.commitment.root)
  assert not sameStateSnapshot(posterior, original)
  assert effects.state.snapshot.value.lookup(provisionRequest(42, @[73'u8]).key).value.bytes == @[0'u8]
  assert posterior.lookup(provisionRequest(42, @[73'u8]).key).value.bytes == @[1'u8, 2, 0, 0, 0]
  let next = prepareContinuationAccumulationService(successor, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
  assert serviceSourceMatches(next, successor.continuationInputs.value, posterior)
  assert not serviceSourceMatches(next, successor.continuationInputs.value, original)
  var retained: PreparedAccumulationContinuationInputs
  block:
    let localPlan = planAccumulationContinuation(completed,
      AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(2),
          digests: ElementLimit(2))).value
    retained = prepareAccumulationContinuationInputs(localPlan, config()).value
  assert retained.continuationInputs.value.invocationServiceCount.value == 1
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Both prepared range inputs and private changed-map candidates are released on success and late backend refusal.
    failHash(1)
    let refused = prepareAccumulationContinuationInputs(effectPlan, config())
    assert refused.batchFailure.provisionError == AccumulationProvisionError.BackendFailure
    failHash(0)
    let owner = prepareAccumulationContinuationInputs(effectPlan, config()).value
    assert array[32, byte](owner.continuationState.value.commitment.root) == array[32, byte](
        expected.commitment.root)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_continuation_inputs", 1000, before, after)
  echo "Accumulation continuation input/state binding passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected exceptions and fixture I/O remain native test failures.
except:
  quit(2)
