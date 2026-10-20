# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_later_runner_arc_release"}

## Genuine later-round runners agree with manual guest composition and preserve exact posterior provenance.

import std/[assertions, envvars, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, report_owned, state_trie, state_safrole, assurances]
import ../../../src/pvm/[initialize, machine, step, gas]
import ../../../src/state/[accumulation_later_runner, accumulation_runner, accumulation_round,
  accumulation_execution, accumulation_continuation, accumulation_continuation_inputs,
  accumulation_continuation_execution, accumulation_reentry, accumulation_inputs,
  accumulation_dispatch, accumulation_skip, accumulation_service, accumulation_invocation,
  accumulation_context, accumulation_machine, accumulation_batch, accumulation_effects,
  accumulation_provisions, accumulation_terminal_provisions, store]
import ../../support/[accumulation_runner_context, accumulation_execution_context,
  accumulation_continuation_execution_context, accumulation_reentry_context,
  pvm_accumulation_provision, arc_evidence]

# Inject faults only after real signed source certificates exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc limits(): AccumulationRunnerLimits =
  ## Two selected operands and finite engine work match the existing reentry oracle policy.
  result = runnerLimits()
  result.fetch.items = ElementLimit(2)
  result.fetch.bytes = ByteLimit(1024)
  result.steps = ExecutionStepLimit(40)
  result.calls = HostCallLimit(8)

proc config(): AccumulationReentryConfig =
  ## Selection/materialization remain caller-driven, with explicit depth at repeated preparation.
  AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(2),
    reports: ElementLimit(4), digests: ElementLimit(8)), operands: executionRoundConfig().operands,
    inputs: executionRoundConfig().inputs)

proc manual(source: PreparedAccumulationContinuationInputs,
    provided = false): CompletedAccumulationContinuation =
  ## Manually compose existing bound service/guest/completion APIs as an independent orchestration oracle.
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  for index in 0..<source.continuationInputs.value.invocationServiceCount.value:
    let service = prepareContinuationAccumulationService(source, InvocationServiceIndex(uint64(
        index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      let policy = if provided: provisionPolicy(2, 1, 2) else: default(AccumulationProvisionLimits)
      runs.add(continuationGuest(source, uint64(index),
          policy)) # Actual engine outcomes, never forged gas or terminals.
    else:
      skips.add(finishUninvokedAccumulation(service).value) # Only real missing/malformed/oversized code skips.
  completeAccumulationContinuation(source, runs, skips, executionLimits()).value

proc manual(source: PreparedAccumulationReentry, provided = false): CompletedAccumulationReentry =
  ## The old manually supplied execution arrays remain the parity oracle at every prepared depth.
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      runs.add(reentryGuest(source, uint64(index),
          provided)) # Resolve the same actual posterior service independently.
    else:
      skips.add(finishUninvokedAccumulation(service).value) # Certified skips retain exact source/prior ownership.
  completeAccumulationReentry(source, runs, skips, executionLimits()).value

proc compare(compared, expectedResult: CompletedAccumulationContinuation,
    priorState: StateStoreSnapshot) =
  ## Compare gas/coverage and complete applied-map roots, preserving the original immutable prior.
  assert compared.executionInfo.value.services == expectedResult.executionInfo.value.services
  assert compared.executionInfo.value.batch.skipped ==
      expectedResult.executionInfo.value.batch.skipped
  assert compared.executionInfo.value.batch.completeInputs
  assert uint64(compared.executionInfo.value.gasUsed) == uint64(
      expectedResult.executionInfo.value.gasUsed)
  for index in 0..<compared.executionInfo.value.services:
    assert uint64(compared.executionGasAt(InvocationServiceIndex(uint64(index))).value.gasUsed) ==
      uint64(expectedResult.executionGasAt(InvocationServiceIndex(uint64(index))).value.gasUsed)
  var candidate = forkStateStore(priorState).value
  var oracle = forkStateStore(priorState).value
  discard applyAccumulationBatch(candidate, compared.executionBatch.value).value
  discard applyAccumulationBatch(oracle, expectedResult.executionBatch.value).value
  assert array[32, byte](candidate.snapshot.value.commitment.root) == array[32, byte](
      oracle.snapshot.value.commitment.root)



proc compare(compared, expectedResult: CompletedAccumulationReentry,
    priorState: StateStoreSnapshot) =
  ## Compare gas/coverage and complete applied-map roots, preserving the original immutable prior.
  assert compared.executionInfo.value.services == expectedResult.executionInfo.value.services
  assert compared.executionInfo.value.batch.skipped ==
      expectedResult.executionInfo.value.batch.skipped
  assert compared.executionInfo.value.batch.completeInputs
  assert uint64(compared.executionInfo.value.gasUsed) == uint64(
      expectedResult.executionInfo.value.gasUsed)
  for index in 0..<compared.executionInfo.value.services:
    assert uint64(compared.executionGasAt(InvocationServiceIndex(uint64(index))).value.gasUsed) ==
      uint64(expectedResult.executionGasAt(InvocationServiceIndex(uint64(index))).value.gasUsed)
  var candidate = forkStateStore(priorState).value
  var oracle = forkStateStore(priorState).value
  discard applyAccumulationBatch(candidate, compared.executionBatch.value).value
  discard applyAccumulationBatch(oracle, expectedResult.executionBatch.value).value
  assert array[32, byte](candidate.snapshot.value.commitment.root) == array[32, byte](
      oracle.snapshot.value.commitment.root)



template failures(source, run: untyped) =
  block:
    # Both public source families must preserve each local refusal instead of fabricating guest panic.
    var policy = limits()
    for parameters in [default(Parameters), runnerParameters(cores = 3), runnerParameters(
        epoch = 13), runnerParameters(queue = 79)]:
      assert run(source, parameters, policy).error == AccumulationLaterRunnerError.InvalidParameters
    policy.contexts.validators = ValidatorCount(9)
    assert run(source, runnerParameters(), policy).error ==
        AccumulationLaterRunnerError.InvalidParameters
    policy = limits()
    policy.completion.services = ElementLimit(1)
    assert run(source, runnerParameters(), policy).error ==
        AccumulationLaterRunnerError.LimitExceeded
    policy = limits()
    policy.preimageBytes = ByteLimit(0)
    assert run(source, runnerParameters(), policy).serviceError ==
        AccumulationServiceError.LimitExceeded
    policy = limits()
    policy.probes = ServiceProbeLimit(0)
    assert run(source, runnerParameters(), policy).invocationError ==
        AccumulationInvocationError.LimitExceeded
    policy = limits()
    policy.contexts.totalBytes = ByteLimit(0)
    assert run(source, runnerParameters(), policy).contextError ==
        AccumulationContextError.LimitExceeded
    policy = limits()
    policy.initialization.envelope = InitializationByteLimit(0)
    assert run(source, runnerParameters(), policy).machineError ==
        AccumulationMachineError.LimitExceeded
    policy = limits()
    policy.fetch.bytes = ByteLimit(0)
    assert run(source, runnerParameters(), policy).dispatchFailure.error ==
        AccumulationDispatchError.LimitExceeded
    policy = limits()
    policy.steps = ExecutionStepLimit(0)
    assert run(source, runnerParameters(), policy).dispatchFailure.executionError ==
        StepError.StepLimitExceeded
    policy = limits()
    policy.cycles = GasCycleLimit(0)
    assert run(source, runnerParameters(), policy).dispatchFailure.executionError ==
        StepError.GasCycleLimitExceeded
    failHash(1)
    let backend = run(source, runnerParameters(), limits())
    failHash(0)
    assert backend.serviceError == AccumulationServiceError.BackendFailure
    failAfter(4) # Original resolution plus the bound adapter's code-key/integrity hashes precede invocation seed hashing.
    let invocationBackend = run(source, runnerParameters(), limits())
    failHash(0)
    assert invocationBackend.error == AccumulationLaterRunnerError.InvocationFailure,
        $invocationBackend.error
    assert invocationBackend.invocationError == AccumulationInvocationError.BackendFailure

proc main() {.raises.} =
  # The supported native runner verifies these static fixture bytes before any real block signing.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let parameters = runnerParameters()
  let policy = limits()
  let continuation = continuationExecutionFixture(base)
  let reentry = reentryFixture(base)
  let actual = runAccumulationContinuation(continuation.source, parameters, policy).value
  compare(actual, manual(continuation.source), continuation.source.continuationState.value)
  assert sameAccumulationInputs(actual.executionContinuation.value.continuationInputs.value,
    continuation.source.continuationInputs.value)
  let completed = runAccumulationReentry(reentry.source, parameters, policy).value
  compare(completed, manual(reentry.source), reentry.source.reentryState.value)
  assert sameAccumulationInputs(completed.executionReentry.value.reentryInputs.value,
      reentry.source.reentryInputs.value)
  for ending in [ExecutionEnding.Panic, ExecutionEnding.Exhausted, ExecutionEnding.HostExhausted,
      ExecutionEnding.Missing]:
    # Explicit gas distinguishes unaffordable basic blocks from underfunded hosts in later rounds.
    let gas = if ending == ExecutionEnding.Exhausted: 1'u64 elif ending ==
        ExecutionEnding.HostExhausted: 200'u64 else: 300'u64
    let context = continuationExecutionFixture(base, first = ending,
        second = ExecutionEnding.Missing, firstGas = gas)
    compare(runAccumulationContinuation(context.source, parameters, policy).value,
      manual(context.source), context.source.continuationState.value)
    let entry = reentryFixture(base, first = ending, second = ExecutionEnding.Missing,
        firstGas = gas)
    compare(runAccumulationReentry(entry.source, parameters, policy).value, manual(entry.source),
        entry.source.reentryState.value)
  for empty in [false, true]:
    # Both explicit stopped queues and genuinely empty queues complete with zero services and gas.
    let entry = reentryFixture(base, stopped = true, empty = empty)
    let stopped = runAccumulationReentry(entry.source, parameters, policy).value
    assert stopped.executionInfo.value.services == 0 and uint64(
        stopped.executionInfo.value.gasUsed) == 0
    assert prepareAccumulationReentry(stopped, config(), AccumulationReentryDepthLimit(10)).error ==
        AccumulationReentryError.Stopped
    assert runAccumulationReentry(entry.source, default(Parameters), policy).error ==
        AccumulationLaterRunnerError.InvalidParameters
  let empty = continuationExecutionFixture(base, empty = true)
  assert runAccumulationContinuation(empty.source, parameters,
      policy).value.executionInfo.value.services == 0
  assert runAccumulationContinuation(empty.source, default(Parameters), policy).error ==
      AccumulationLaterRunnerError.InvalidParameters
  let uninitialized = default(AccumulationLaterRunnerResult[CompletedAccumulationContinuation])
  assert uninitialized.error ==
      AccumulationLaterRunnerError.Uninitialized
  assert runAccumulationContinuation(default(PreparedAccumulationContinuationInputs), parameters,
      policy).error == AccumulationLaterRunnerError.InvalidSource
  assert runAccumulationReentry(default(PreparedAccumulationReentry), parameters, policy).error ==
      AccumulationLaterRunnerError.InvalidSource
  failures(continuation.source, runAccumulationContinuation)
  failures(reentry.source, runAccumulationReentry)
  var short = policy
  short.completion.batch.provisions.contexts = ElementLimit(0)
  assert runAccumulationContinuation(continuation.source, parameters,
      short).continuationFailure.batchFailure.error == AccumulationBatchError.LimitExceeded
  assert runAccumulationReentry(reentry.source, parameters,
      short).reentryFailure.batchFailure.error == AccumulationBatchError.LimitExceeded
  short = policy
  short.completion.batch.provisions.encodedBytes = ByteLimit(0)
  assert runAccumulationContinuation(continuation.source, parameters,
      short).continuationFailure.batchFailure.provisionError ==
      AccumulationProvisionError.LimitExceeded
  assert runAccumulationReentry(reentry.source, parameters,
      short).reentryFailure.batchFailure.provisionError == AccumulationProvisionError.LimitExceeded
  short = policy
  short.steps = ExecutionStepLimit(1)
  assert runAccumulationContinuation(continuation.source, parameters, short).error ==
      AccumulationLaterRunnerError.None
  assert runAccumulationReentry(reentry.source, parameters, short).error ==
      AccumulationLaterRunnerError.None
  let lateContinuation = continuationExecutionFixture(base, second = ExecutionEnding.Panic)
  let lateReentry = reentryFixture(base, second = ExecutionEnding.Panic)
  assert runAccumulationContinuation(lateContinuation.source, parameters,
      short).dispatchFailure.executionError == StepError.StepLimitExceeded
  assert runAccumulationReentry(lateReentry.source, parameters,
      short).dispatchFailure.executionError == StepError.StepLimitExceeded
  var withProvisions = policy
  withProvisions.provisions = provisionPolicy(2, 1, 2)
  let provided = continuationProvidedFixture(base)
  assert not sameStateSnapshot(provided.source.continuationState.value,
      provided.initial.state.snapshot.value)
  compare(runAccumulationContinuation(provided.source, parameters, withProvisions).value,
    manual(provided.source, true), provided.source.continuationState.value)
  let supplied = reentryFixture(base, provided = true)
  assert not sameStateSnapshot(supplied.source.reentryState.value,
      supplied.initial.state.snapshot.value)
  compare(runAccumulationReentry(supplied.source, parameters, withProvisions).value,
    manual(supplied.source, true), supplied.source.reentryState.value)
  # The retained earlier continuation still has outstanding requests, so this exercises fresh real provides.
  let unfulfilled = supplied.source.reentrySource.value.executionContinuation.value
  let unfulfilledPrior = unfulfilled.continuationState.value
  let fulfilled = runAccumulationContinuation(unfulfilled, parameters, withProvisions).value
  compare(fulfilled, manual(unfulfilled, true), unfulfilledPrior)
  var fresh = forkStateStore(unfulfilledPrior).value
  discard applyAccumulationBatch(fresh, fulfilled.executionBatch.value).value
  assert array[32, byte](fresh.snapshot.value.commitment.root) == array[32, byte](
      supplied.source.reentryState.value.commitment.root)
  assert sameStateSnapshot(unfulfilled.continuationState.value, unfulfilledPrior)
  assert runAccumulationContinuation(unfulfilled, parameters, policy).dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  var noCopy = withProvisions
  noCopy.copyBytes = MemoryByteLimit(0)
  assert runAccumulationContinuation(unfulfilled, parameters, noCopy).dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  var noUnion = withProvisions
  noUnion.completion.batch.provisions.values.items = ElementLimit(0)
  assert runAccumulationContinuation(unfulfilled, parameters,
      noUnion).continuationFailure.batchFailure.provisionError ==
      AccumulationProvisionError.LimitExceeded
  # Eligibility follows chain parameters on both source paths; local limits do not grant execution.
  let skippedContinuation = runAccumulationContinuation(continuation.source, runnerParameters(
      code = 0), policy).value
  let skippedReentry = runAccumulationReentry(reentry.source, runnerParameters(code = 0), policy).value
  assert skippedContinuation.executionInfo.value.batch.skipped == 2 and uint64(
      skippedContinuation.executionInfo.value.gasUsed) == 0
  assert skippedReentry.executionInfo.value.batch.skipped == 2 and uint64(
      skippedReentry.executionInfo.value.gasUsed) == 0
  # Advance several genuine depths; new runners consume prepared source state without replaying older rounds.
  let tail = @[reentryReady(base, 68, [100000'u64, 100000]), reentryReady(base, 69, [100000'u64,
      100000]), reentryReady(base, 70, [0'u64])]
  var next = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail).source
  for depth in 1..4:
    assert uint64(next.reentryInfo.value.depth) == uint64(depth)
    let run = runAccumulationReentry(next, parameters, policy).value
    compare(run, manual(next), next.reentryState.value)
    if depth < 4:
      next = prepareAccumulationReentry(run, config(), AccumulationReentryDepthLimit(
          4)).value # Only the just-completed batch advances.
    else:
      assert not run.executionInfo.value.round.dispatch # Last entry is genuinely stopped.
  var retained: CompletedAccumulationReentry
  var retainedContinuation: CompletedAccumulationContinuation
  block:
    let detached = reentryFixture(base)
    retained = runAccumulationReentry(detached.source, parameters,
        policy).value # Completion retains actual source/state after local handles die.
  block:
    let detached = continuationExecutionFixture(base)
    retainedContinuation = runAccumulationContinuation(detached.source, parameters,
        policy).value # The other completion family also retains its detached source.
  assert uint64(retained.executionInfo.value.gasUsed) == 44
  assert uint64(retainedContinuation.executionInfo.value.gasUsed) == 44
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Success and late-service refusal release guest machines, both context copies and all temporary arrays.
    assert uint64(runAccumulationContinuation(continuation.source, parameters,
        policy).value.executionInfo.value.gasUsed) == 44
    assert uint64(runAccumulationReentry(reentry.source, parameters,
        policy).value.executionInfo.value.gasUsed) == 44
    assert runAccumulationContinuation(lateContinuation.source, parameters,
        short).dispatchFailure.executionError == StepError.StepLimitExceeded
    assert runAccumulationReentry(lateReentry.source, parameters,
        short).dispatchFailure.executionError == StepError.StepLimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_later_runner", 1000, before, after)
  echo "Bound later accumulation runners passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected fixture I/O and exceptions remain failed native runs.
except:
  quit(2)
