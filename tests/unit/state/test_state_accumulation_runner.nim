# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_runner_arc_release"}

## Genuine initial-round orchestration agrees with manual PVM completion and refuses atomically.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/pvm/initialize as pvm_initialize
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/gas as pvm_gas
import ../../../src/state/accumulation_runner as state_accumulation_runner
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_context as state_accumulation_context
import ../../../src/state/accumulation_machine as state_accumulation_machine
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/store as state_store
import ../../support/state_accumulation_execution_context
import ../../support/state_accumulation_runner_context
import ../../support/state_accumulation_batch_context
import ../../support/state_accumulation_provision_integration
import ../../support/pvm_accumulation_provision
import ../../support/testing_arc_evidence

# Backend refusal must retain a local typed error, never become a protocol guest panic.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc parity(fixture: ExecutionFixture, first, second: ExecutionEnding) =
  ## Real manually executed guests/skips provide the independent composition oracle, including normalized gas.
  let prior = fixture.state.snapshot.value
  var executions: seq[AccumulationDispatchResult] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  for index, ending in [first, second]:
    if ending == ExecutionEnding.Missing:
      skipped.add(executionSkip(fixture, uint64(index))) # Certified unavailable code needs no PVM.
    else:
      executions.add(executionGuest(fixture, uint64(index))) # Halt/panic/OOG come from actual engine work.
  let manual = completeBlockAccumulation(fixture.round, executions, skipped, executionLimits()).value
  let result = runBlockAccumulation(fixture.round, runnerParameters(), runnerLimits())
  assert result.error == AccumulationRunnerError.None, $result.error
  let plan = result.value
  assert plan.executionInfo.value.services == 2
  assert uint64(plan.executionInfo.value.gasUsed) == uint64(manual.executionInfo.value.gasUsed)
  assert plan.executionInfo.value.batch.skipped == manual.executionInfo.value.batch.skipped
  for index in 0..<2:
    assert uint64(plan.executionGasAt(InvocationServiceIndex(uint64(index))).value.gasUsed) ==
      uint64(manual.executionGasAt(InvocationServiceIndex(uint64(index))).value.gasUsed)
  assert sameAccumulationInputs(plan.executionRound.value.roundProjection.value.roundInputs.value,
    fixture.round.roundProjection.value.roundInputs.value)
  var candidate = fixture.state
  var oracle = fixture.state
  assert applyAccumulationBatch(candidate, plan.executionBatch.value).error ==
      AccumulationBatchError.None
  assert applyAccumulationBatch(oracle, manual.executionBatch.value).error ==
      AccumulationBatchError.None
  assert array[32, byte](candidate.snapshot.value.commitment.root) == array[32, byte](
      oracle.snapshot.value.commitment.root)
  assert sameStateSnapshot(fixture.state.snapshot.value, prior) # Both paths prepare privately.

proc main() {.raises.} =
  # The supported runner supplies the checksum-verified static report fixture.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let parameters = runnerParameters()
  let limits = runnerLimits()
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.signed.withAvailable = true
  let fixture = executionFixture(base, executionOptions0)
  parity(fixture, ExecutionEnding.Halt, ExecutionEnding.Halt)
  for ending in [ExecutionEnding.Panic, ExecutionEnding.Exhausted, ExecutionEnding.HostExhausted,
      ExecutionEnding.Missing]:
    var executionOptions1 = executionFixtureConfig()
    executionOptions1.first = ending
    executionOptions1.second = ExecutionEnding.Missing
    parity(executionFixture(base, executionOptions1),
      ending, ExecutionEnding.Missing) # Includes both out-of-gas charging branches and all-skip coverage.
  var executionOptions2 = executionFixtureConfig()
  executionOptions2.empty = true
  let empty = executionFixture(base, executionOptions2)
  var zero = limits
  zero.completion.services = ElementLimit(0)
  let emptyPlan = runBlockAccumulation(empty.round, parameters, zero).value
  assert emptyPlan.executionInfo.value.services == 0 and uint64(
      emptyPlan.executionInfo.value.gasUsed) == 0
  assert runBlockAccumulation(default(BlockAccumulationRound), parameters, limits).error ==
    AccumulationRunnerError.InvalidRound
  for config in [default(Parameters), runnerParameters(cores = 3), runnerParameters(epoch = 13),
      runnerParameters(queue = 79)]:
    assert runBlockAccumulation(fixture.round, config, limits).error ==
        AccumulationRunnerError.InvalidParameters
    assert runBlockAccumulation(empty.round, config, zero).error ==
        AccumulationRunnerError.InvalidParameters
  var policy = limits
  policy.contexts.validators = ValidatorCount(9)
  assert runBlockAccumulation(fixture.round, parameters, policy).error ==
      AccumulationRunnerError.InvalidParameters
  policy = limits
  policy.completion.services = ElementLimit(1)
  assert runBlockAccumulation(fixture.round, parameters, policy).error ==
      AccumulationRunnerError.LimitExceeded
  policy = limits
  policy.preimageBytes = ByteLimit(0)
  assert runBlockAccumulation(fixture.round, parameters, policy).serviceError ==
      AccumulationServiceError.LimitExceeded
  policy = limits
  policy.probes = ServiceProbeLimit(0)
  assert runBlockAccumulation(fixture.round, parameters, policy).invocationError ==
      AccumulationInvocationError.LimitExceeded
  policy = limits
  policy.contexts.totalBytes = ByteLimit(0)
  assert runBlockAccumulation(fixture.round, parameters, policy).contextError ==
      AccumulationContextError.LimitExceeded
  policy = limits
  policy.initialization.envelope = InitializationByteLimit(0)
  assert runBlockAccumulation(fixture.round, parameters, policy).machineError ==
      AccumulationMachineError.LimitExceeded
  policy = limits
  policy.fetch.bytes = ByteLimit(0)
  assert runBlockAccumulation(fixture.round, parameters, policy).dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  policy = limits
  policy.steps = ExecutionStepLimit(0)
  let engine = runBlockAccumulation(fixture.round, parameters, policy)
  assert engine.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
  assert engine.dispatchFailure.executionError == StepError.StepLimitExceeded
  policy = limits
  policy.completion.batch.provisions.contexts = ElementLimit(0)
  let incomplete = runBlockAccumulation(fixture.round, parameters, policy)
  assert incomplete.error == AccumulationRunnerError.CompletionFailure, $incomplete.error
  assert incomplete.completionFailure.batchFailure.error == AccumulationBatchError.LimitExceeded
  # A later service's larger checkpoint program exceeds a ceiling that the first ready guest passes.
  var executionOptions3 = executionFixtureConfig()
  executionOptions3.second = ExecutionEnding.Panic
  let late = executionFixture(base, executionOptions3)
  let latePrior = late.state.snapshot.value
  policy = limits
  policy.steps = ExecutionStepLimit(1)
  assert runBlockAccumulation(fixture.round, parameters, policy).error ==
      AccumulationRunnerError.None
  assert runBlockAccumulation(late.round, parameters, policy).dispatchFailure.executionError ==
      StepError.StepLimitExceeded
  policy = limits
  policy.calls = HostCallLimit(0)
  assert runBlockAccumulation(late.round, parameters, policy).dispatchFailure.executionError ==
      StepError.HostCallLimitExceeded
  policy = limits
  policy.cycles = GasCycleLimit(0)
  assert runBlockAccumulation(fixture.round, parameters, policy).dispatchFailure.executionError ==
      StepError.GasCycleLimitExceeded
  assert sameStateSnapshot(late.state.snapshot.value, latePrior)
  # Protocol code eligibility comes from Parameters; zero code size skips genuine nonempty programs.
  let oversized = runBlockAccumulation(fixture.round, runnerParameters(code = 0), limits).value
  assert oversized.executionInfo.value.batch.skipped == 2 and uint64(
      oversized.executionInfo.value.gasUsed) == 0
  # Real provides use existing checkpoint/union machinery; failure cannot return an earlier successful guest.
  var executionOptions4 = executionFixtureConfig()
  executionOptions4.firstProgram = @[255'u8]
  let malformed = executionFixture(base, executionOptions4)
  assert runBlockAccumulation(malformed.round, parameters,
      limits).value.executionInfo.value.batch.skipped == 1
  var executionOptions5 = executionFixtureConfig()
  executionOptions5.firstProgram = @[0'u8, 1]
  let invalidEnvelope = executionFixture(base, executionOptions5)
  assert runBlockAccumulation(invalidEnvelope.round, parameters, limits).machineError ==
    AccumulationMachineError.InvalidEnvelope
  var executionOptions6 = executionFixtureConfig()
  executionOptions6.omitAuthorizationQueue = true
  let missingContexts = executionFixture(base, executionOptions6)
  assert runBlockAccumulation(missingContexts.round, parameters, limits).contextError ==
      AccumulationContextError.MissingState
  failHash(1)
  let backend = runBlockAccumulation(fixture.round, parameters, limits)
  failHash(0)
  assert backend.error == AccumulationRunnerError.ServiceFailure, $backend.error
  assert backend.serviceError == AccumulationServiceError.BackendFailure
  failAfter(2) # Permit the code-key and code-integrity hashes; refuse the invocation seed hash.
  let invocationBackend = runBlockAccumulation(fixture.round, parameters, limits)
  failHash(0)
  assert invocationBackend.error == AccumulationRunnerError.InvocationFailure,
      $invocationBackend.error
  assert invocationBackend.invocationError == AccumulationInvocationError.BackendFailure
  var executionOptions7 = executionFixtureConfig()
  executionOptions7.firstProgram = runnerProgram(BatchEnding.Halt)
  executionOptions7.secondProgram = runnerProgram(BatchEnding.Panic)
  executionOptions7.signed.extra = @[integrationRequest(42, @[73'u8]), integrationRequest(99, @[81'u8])]
  let provided = executionFixture(base, executionOptions7)
  policy = limits
  policy.steps = ExecutionStepLimit(100)
  policy.calls = HostCallLimit(10)
  policy.provisions = provisionPolicy(2, 1, 2)
  let supplied = runBlockAccumulation(provided.round, parameters, policy)
  assert supplied.error == AccumulationRunnerError.None, $supplied.error
  assert supplied.value.executionInfo.value.batch.completeInputs
  assert supplied.value.executionInfo.value.batch.terminal.provisions.items == 2
  let manualProvided = completeBlockAccumulation(provided.round,
    [executionGuest(provided, 0, provisions = policy.provisions),
     executionGuest(provided, 1, provisions = policy.provisions)], [], policy.completion).value
  assert uint64(manualProvided.executionInfo.value.gasUsed) == uint64(
      supplied.value.executionInfo.value.gasUsed)
  var published = provided.state
  var expected = provided.state
  discard applyAccumulationBatch(published, supplied.value.executionBatch.value).value
  discard applyAccumulationBatch(expected, manualProvided.executionBatch.value).value
  assert array[32, byte](published.snapshot.value.commitment.root) == array[32, byte](
      expected.snapshot.value.commitment.root)
  policy.copyBytes = MemoryByteLimit(0)
  assert runBlockAccumulation(provided.round, parameters, policy).dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  policy.copyBytes = limits.copyBytes
  policy.provisions = default(AccumulationProvisionLimits)
  assert runBlockAccumulation(provided.round, parameters, policy).dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  policy.provisions = provisionPolicy(2, 1, 2)
  policy.completion.batch.provisions.values.items = ElementLimit(0)
  let unionFailure = runBlockAccumulation(provided.round, parameters, policy)
  assert unionFailure.error == AccumulationRunnerError.CompletionFailure, $unionFailure.error
  assert unionFailure.completionFailure.batchFailure.error == AccumulationBatchError.TerminalFailure
  var latePolicy = limits
  latePolicy.steps = ExecutionStepLimit(1)
  var retained: CompletedBlockAccumulation
  block:
    let source = executionFixture(base)
    retained = runBlockAccumulation(source.round, parameters,
        limits).value # Retain the entire certified source graph.
  assert uint64(retained.executionInfo.value.gasUsed) == 44
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let completed = runBlockAccumulation(fixture.round, parameters, limits).value
    assert uint64(completed.executionInfo.value.gasUsed) == 44
    assert runBlockAccumulation(late.round, parameters,
        latePolicy).dispatchFailure.executionError == StepError.StepLimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_runner", 1000, before, after)
  echo "Bound accumulation runner passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected I/O/exceptions must fail the suite.
except:
  quit(2)
