# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_continuation_invocation_arc_release"}

## Genuine continuation bootstraps bind account/input identity and posterior block entropy through execution.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_continuation_invocation as state_accumulation_continuation_invocation
import ../../../src/state/accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/accumulation_machine as state_accumulation_machine
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/pvm/initialize as pvm_initialize
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../support/state_accumulation_execution_context
import ../../support/state_accumulation_batch_context
import ../../support/pvm_accumulation_context
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Refuse only the native test hash provider after signed fixture construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

# The first batch reserves the whole budget in allowances; real 22-gas halts release a report-only continuation.
proc context(base: OwnedReport, missing = false): PreparedAccumulationContinuationInputs =
  let ending = if missing: ExecutionEnding.Missing else: ExecutionEnding.Halt
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = ending
  executionOptions0.signed.ready = @[ReadyItem(report: reportFor(base, 0, [100'u64]),
      dependencies: @[])]
  var fixture = executionFixture(base, executionOptions0)
  var roundConfig = executionRoundConfig()
  roundConfig.blockGas = Gas(200000)
  fixture.round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value,
      roundConfig).value
  let complete = if missing:
    completeBlockAccumulation(fixture.round, [executionGuest(fixture, 1)],
      [executionSkip(fixture, 0)], executionLimits()).value
  else:
    completeBlockAccumulation(fixture.round,
      [executionGuest(fixture, 0), executionGuest(fixture, 1)], [], executionLimits()).value
  let plan = planAccumulationContinuation(complete,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(1),
      digests: ElementLimit(1))).value
  assert uint64(plan.continuationInfo.value.completedPrefix) == 0
  assert uint64(plan.continuationInfo.value.prefix) == 1
  prepareAccumulationContinuationInputs(plan,
    AccumulationContinuationInputConfig(operands: roundConfig.operands,
        inputs: roundConfig.inputs)).value

# Explicit code policy remains independent from the retained block/source certificate.
proc config(): AccumulationServiceConfig =
  AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Preserve binary source bytes before genuine signing.
  let base = decodeOwnedReport(bytes, 2).value
  let source = context(base)
  let original = source.continuationState.value
  let bound = prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(0),
    config(), ServiceProbeLimit(1)).value
  let projection = bound.bootstrapProjection.value
  let info = projection.bootstrapInfo.value
  let service = projection.bootstrapService.value
  assert serviceSourceMatches(service, source.continuationInputs.value, original)
  assert uint32(info.slot) == 2 and uint32(info.service) == 42 and uint64(info.inputs) == 1
  assert uint64(service.serviceInfo.value.gas) == 100
  assert projection.bootstrapArguments.value == @[2'u8, 42, 1] # Literal E(slot, service, selected input count).
  let completed = source.continuationPlan.value.continuationSource.value
  let queue = completed.executionRound.value.roundBlockQueue.value
  let stage = queue.accumulationAdmission.value.reportBlockStage.value.value
  let posterior = decodeStateEntropy(stage.snapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  let parent = decodeStateEntropy(original.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  assert array[32, byte](posterior) != array[32, byte](parent)
  assert array[32, byte](info.entropy) == array[32, byte](posterior)
  assert uint32(info.nextService) == uint32(initialAccumulationService(ServiceIndex(42), posterior,
      HeaderSlot(2)).value)
  assert uint32(info.nextService) != uint32(initialAccumulationService(ServiceIndex(42), parent,
      HeaderSlot(2)).value)
  assert sameStateSnapshot(bound.bootstrapContinuation.value.continuationState.value, original)
  # Independently re-prepared input owners do not substitute for this exact retained provenance.
  let other = prepareAccumulationContinuationInputs(source.continuationPlan.value,
    AccumulationContinuationInputConfig(operands: executionRoundConfig().operands,
      inputs: executionRoundConfig().inputs)).value
  assert not serviceSourceMatches(service, other.continuationInputs.value, original)
  var observed = projection.bootstrapInfo.value
  observed.entropy = parent
  var arguments = projection.bootstrapArguments.value
  arguments[0] = 9
  assert array[32, byte](projection.bootstrapInfo.value.entropy) == array[32, byte](posterior)
  assert projection.bootstrapArguments.value == @[2'u8, 42, 1]
  let empty = default(ContinuationAccumulationInvocation)
  assert empty.bootstrapProjection.error == AccumulationContinuationInvocationError.Uninitialized
  assert empty.bootstrapContinuation.error == AccumulationContinuationInvocationError.Uninitialized
  let invalid = prepareContinuationAccumulationInvocation(default(
      PreparedAccumulationContinuationInputs),
    InvocationServiceIndex(0), config(), ServiceProbeLimit(1))
  assert invalid.error == AccumulationContinuationInvocationError.InvalidInputs
  assert prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(high(uint64)),
    config(), ServiceProbeLimit(1)).serviceError == AccumulationServiceError.InvalidIndex
  var limited = config()
  limited.preimageBytes = ByteLimit(0)
  assert prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(0),
    limited, ServiceProbeLimit(1)).serviceError == AccumulationServiceError.LimitExceeded
  let exhausted = prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(0),
    config(), ServiceProbeLimit(0))
  assert exhausted.invocationError == AccumulationInvocationError.LimitExceeded
  let missing = context(base, true)
  assert prepareContinuationAccumulationInvocation(missing, InvocationServiceIndex(0),
    config(), ServiceProbeLimit(1)).invocationError == AccumulationInvocationError.CodeUnavailable
  failHash(1)
  assert prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(0),
    config(), ServiceProbeLimit(1)).serviceError == AccumulationServiceError.BackendFailure
  failHash(0)
  # Existing PVM initialization/execution consumes this exact bound projection without new native hosts.
  let cpu = initializeAccumulationMachine(projection, InitializationLimits(
    envelope: InitializationByteLimit(512), program: ProgramByteLimit(256), jumps: JumpCountLimit(0),
    pages: PageLimit(5))).value
  let initial = cpu.accumulationMachine.value.machineInfo.value
  assert uint64(initial.gas) == 100 and uint32(initial.pc) == 5
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  let execution = executeAccumulationMachine(cpu, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(1), bytes: ByteLimit(512),
      operand: OperandLimits(maxBytes: ByteLimit(512))), MemoryByteLimit(32),
    ExecutionStepLimit(20), HostCallLimit(4), GasCycleLimit(1000), contexts)
  assert execution.error == AccumulationDispatchError.None
  let outcome = normalizeAccumulationOutcome(execution).value.outcomeInfo.value
  assert outcome.termination == AccumulationTermination.Halt and uint64(outcome.gasUsed) == 22
  assert sameStateSnapshot(source.continuationState.value, original)
  var retained: ContinuationAccumulationInvocation
  block:
    let local = context(base)
    retained = prepareContinuationAccumulationInvocation(local, InvocationServiceIndex(0),
      config(), ServiceProbeLimit(1)).value
  assert retained.bootstrapProjection.value.bootstrapArguments.value == @[2'u8, 42, 1]
  assert retained.bootstrapContinuation.value.continuationInputs.value.invocationServiceCount.value == 1
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Both complete source/projection owners and late probe-refused service candidates are released.
    let success = prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(0),
      config(), ServiceProbeLimit(1))
    assert success.value.bootstrapProjection.value.bootstrapArguments.value == @[2'u8, 42, 1]
    let refusal = prepareContinuationAccumulationInvocation(source, InvocationServiceIndex(0),
      config(), ServiceProbeLimit(0))
    assert refusal.invocationError == AccumulationInvocationError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_continuation_invocation", 1000, before, after)
  echo "Accumulation continuation invocation binding passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected exceptions and missing fixture transport remain native failures.
except:
  quit(2)
