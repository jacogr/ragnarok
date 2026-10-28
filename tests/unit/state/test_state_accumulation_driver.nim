# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_driver_arc_release"}

## Real signed report-only histories stop under an explicit cap and agree with manual guest/advance/finalization.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_outputs as codec_state_outputs
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../../src/state/accumulation_driver as state_accumulation_driver
import ../../../src/state/accumulation_runner as state_accumulation_runner
import ../../../src/state/accumulation_later_runner as state_accumulation_later_runner
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ../../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
import ../../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_outputs as state_accumulation_outputs
import ../../../src/state/store as state_store
import ../../support/state_accumulation_runner_context
import ../../support/state_accumulation_execution_context
import ../../support/state_accumulation_continuation_execution_context
import ../../support/state_accumulation_reentry_context
import ../../support/pvm_accumulation_context
import ../../support/pvm_accumulation_provision
import ../../support/testing_arc_evidence

# Preflight depth refusal and idle completion must not require any hashing.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc limits(depth = 4'u64): AccumulationDriverLimits =
  ## One shared preparation policy and independent guest bounds apply separately at each admitted entry.
  var execution = runnerLimits()
  execution.fetch.items = ElementLimit(2)
  execution.fetch.bytes = ByteLimit(1024)
  AccumulationDriverLimits(preparation: AccumulationReentryConfig(
    selection: AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(4),
      digests: ElementLimit(8)), operands: executionRoundConfig().operands,
      inputs: executionRoundConfig().inputs), execution: execution,
    depth: AccumulationReentryDepthLimit(depth))

proc outputLimits(): AccumulationOutputHistoryLimits =
  ## Finalization is a separate consumer; these ceilings cover every authored stopped history.
  AccumulationOutputHistoryLimits(rounds: ElementLimit(8), executions: ElementLimit(16),
    log: OutputLogConfig(items: ElementLimit(16), maxBytes: ByteLimit(1000)))

proc initial(source: PreparedAccumulationReentry): CompletedBlockAccumulation =
  ## Extract the genuine already-completed initial root, without replaying its guests or replacing its source.
  source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value

proc manual(source: PreparedAccumulationContinuationInputs,
    provided: bool): CompletedAccumulationContinuation =
  ## Independently compose the prior service, PVM and complete-batch APIs for the manual oracle.
  var executions: seq[AccumulationDispatchResult] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  for index in 0..<source.continuationInputs.value.invocationServiceCount.value:
    let service = prepareContinuationAccumulationService(source, InvocationServiceIndex(uint64(
        index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      let capture = if provided: provisionPolicy(2, 1, 2) else: default(AccumulationProvisionLimits)
      executions.add(continuationGuest(source, uint64(index), capture)) # Real gas and terminal effects only.
    else:
      skipped.add(finishUninvokedAccumulation(service).value) # Genuine code-unavailable alternatives alone skip.
  completeAccumulationContinuation(source, executions, skipped, executionLimits()).value

proc manual(source: PreparedAccumulationReentry, provided: bool): CompletedAccumulationReentry =
  ## Later manual entries use the same concrete completion API at every depth.
  var executions: seq[AccumulationDispatchResult] = @[]
  var skipped: seq[SkippedAccumulation] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      executions.add(reentryGuest(source, uint64(index),
          provided)) # Derive exact posterior source and block entropy.
    else:
      skipped.add(finishUninvokedAccumulation(service).value) # Do not fabricate empty terminal effects.
  completeAccumulationReentry(source, executions, skipped, executionLimits()).value

proc manualFinal(source: CompletedBlockAccumulation, policy: AccumulationDriverLimits,
    provided: bool): PreparedFinalAccumulation =
  ## Manual selection/execution/advance is independent of the new driver and later runners.
  let selected = planAccumulationContinuation(source, policy.preparation.selection).value
  let inputs = prepareAccumulationContinuationInputs(selected, AccumulationContinuationInputConfig(
    operands: policy.preparation.operands, inputs: policy.preparation.inputs)).value
  let continuation = manual(inputs, provided)
  if not continuation.executionInfo.value.round.dispatch:
    return prepareFinalAccumulation(continuation, outputLimits()).value # Idle continuation is already terminal.
  var entry = prepareAccumulationReentry(continuation, policy.preparation).value
  while true:
    # Test fixtures use at most four reentries; enforce the same explicit cap in the independent oracle.
    assert uint64(entry.reentryInfo.value.depth) <= uint64(policy.depth)
    let completed = manual(entry, provided)
    if not completed.executionInfo.value.round.dispatch:
      return prepareFinalAccumulation(completed, outputLimits()).value # No live prefix can finalize.
    entry = prepareAccumulationReentry(completed, policy.preparation,
        policy.depth).value # Apply only the immediate batch.

proc finalized(source: StoppedAccumulation): PreparedFinalAccumulation =
  ## Both genuine terminal kinds feed existing finalization directly, without a new state construction escape.
  case source.stoppedKind
  of StoppedAccumulationKind.Continuation:
    assert not source.stoppedContinuation.executionInfo.value.round.dispatch
    prepareFinalAccumulation(source.stoppedContinuation, outputLimits()).value
  of StoppedAccumulationKind.Reentry:
    assert not source.stoppedReentry.executionInfo.value.round.dispatch
    prepareFinalAccumulation(source.stoppedReentry, outputLimits()).value
  else:
    assert false, "default stopped owner" # Tests never treat an uninitialized owner as terminal.
    default(PreparedFinalAccumulation)

proc compare(source: CompletedBlockAccumulation, policy: AccumulationDriverLimits,
    provided = false): StoppedAccumulation =
  ## Complete root/output parity with manual execution also proves original parent handles remain immutable.
  let run = driveAccumulation(source, runnerParameters(), policy)
  assert run.error == AccumulationDriverError.None, $run.error
  let actual = finalized(run.value)
  let expected = manualFinal(source, policy, provided)
  let info = actual.finalAccumulationInfo.value
  let oracle = expected.finalAccumulationInfo.value
  assert uint64(info.completedPrefix) == uint64(oracle.completedPrefix)
  assert info.pendingReports == oracle.pendingReports
  assert uint64(info.remainingGas) == uint64(oracle.remainingGas)
  assert info.outputs.rounds == oracle.outputs.rounds and info.outputs.outputs ==
      oracle.outputs.outputs
  assert array[32, byte](actual.finalAccumulationState.value.commitment.root) ==
    array[32, byte](expected.finalAccumulationState.value.commitment.root)
  run.value

proc yieldProgram(): seq[byte] =
  ## Literal program yields the padded slot/service/input-count tuple and halts, exposing history union ordering.
  result = @[0'u8]
  for octet in pvmEnvelope([0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 27, 50, 0, 191, 0]):
    result.add(octet) # Full service framing retains the zero-length metadata prefix.

proc main() {.raises.} =
  # Use checksum-verified static bytes before real parent commitments and block signatures are constructed.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let parameters = runnerParameters()
  let policy = limits()
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.empty = true
  let empty = executionFixture(base, executionOptions0)
  let emptyInitial = runBlockAccumulation(empty.round, parameters, policy.execution).value
  failHash(1)
  let idle = driveAccumulation(emptyInitial, parameters, limits(0)).value
  assert idle.stoppedKind == StoppedAccumulationKind.Continuation
  assert idle.stoppedContinuation.executionInfo.value.services == 0
  assert hashCalls() == 0
  failHash(0)
  discard compare(emptyInitial, limits(0))
  let simple = executionFixture(base)
  let simpleInitial = runBlockAccumulation(simple.round, parameters, policy.execution).value
  block:
    # Two genuine initial guests already ran; an idle continuation must not replay their code/hash work.
    failHash(1)
    let noReplay = driveAccumulation(simpleInitial, parameters, limits(0))
    assert noReplay.error == AccumulationDriverError.None
    assert hashCalls() == 0
    failHash(0)
  let simpleStop = compare(simpleInitial, limits(0))
  assert simpleStop.stoppedKind == StoppedAccumulationKind.Continuation
  assert uint64(finalized(simpleStop).finalAccumulationInfo.value.remainingGas) == 299956
  let blocked = reentryFixture(base, stopped = true)
  let blockedStop = compare(initial(blocked.source), limits(0))
  assert blockedStop.stoppedKind == StoppedAccumulationKind.Continuation
  assert finalized(blockedStop).finalAccumulationInfo.value.pendingReports ==
      3 # A cheaper later report cannot bypass the unaffordable head.
  let one = continuationExecutionFixture(base)
  let oneInitial = one.source.continuationPlan.value.continuationSource.value
  let oneStop = compare(oneInitial, limits(1))
  assert oneStop.stoppedKind == StoppedAccumulationKind.Reentry
  assert uint64(oneStop.stoppedReentry.executionInfo.value.round.depth) == 1
  let tail = @[reentryReady(base, 68, [100000'u64, 100000]),
    reentryReady(base, 69, [100000'u64, 100000]), reentryReady(base, 70, [0'u64])]
  let fixture = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail)
  let root = initial(fixture.source)
  let prior = fixture.initial.state.snapshot.value
  let stopped = compare(root, policy)
  assert stopped.stoppedKind == StoppedAccumulationKind.Reentry
  let terminal = stopped.stoppedReentry
  assert uint64(terminal.executionInfo.value.round.depth) == 4
  assert uint64(terminal.executionInfo.value.round.completedPrefix) == 7
  assert uint64(terminal.executionInfo.value.round.budget) == 200780
  assert sameAccumulationInputs(terminal.executionReentry.value.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value.executionRound.value.roundProjection.value.roundInputs.value,
    root.executionRound.value.roundProjection.value.roundInputs.value)
  assert sameStateSnapshot(fixture.initial.state.snapshot.value, prior)
  discard compare(root, limits(high(uint64))) # Full-width policy is never converted to a storage extent.
  failHash(1)
  assert driveAccumulation(root, parameters, limits(0)).error ==
      AccumulationDriverError.DepthExceeded
  assert hashCalls() == 0 # Known insufficient cap refuses before input application or guest code lookup.
  failHash(0)
  for cap in [1'u64, 2, 3]:
    assert driveAccumulation(root, parameters, limits(cap)).error ==
        AccumulationDriverError.DepthExceeded # Terminal depth counts too.
  for ending in [ExecutionEnding.Panic, ExecutionEnding.Exhausted, ExecutionEnding.HostExhausted,
      ExecutionEnding.Missing]:
    let gas = if ending == ExecutionEnding.Exhausted: 1'u64 elif ending ==
        ExecutionEnding.HostExhausted: 200'u64 else: 300'u64
    let context = reentryFixture(base, first = ending, second = ExecutionEnding.Missing,
        firstGas = gas)
    discard compare(initial(context.source), policy) # Panic, two OOG branches and all-skip histories use actual gas.
  let provided = reentryFixture(base, provided = true)
  var withProvisions = policy
  withProvisions.execution.provisions = provisionPolicy(2, 1, 2)
  discard compare(initial(provided.source), withProvisions,
      true) # Fulfill genuine outstanding requests once before later state is observed.
  let yielded = reentryFixture(base, firstProgram = yieldProgram(), secondProgram = yieldProgram())
  let yields = compare(initial(yielded.source), policy)
  assert finalized(yields).finalAccumulationInfo.value.outputs.outputs == 4
  let defaultStopped = default(StoppedAccumulation)
  assert defaultStopped.stoppedKind == StoppedAccumulationKind.Uninitialized
  let invalid = default(AccumulationDriverResult)
  assert invalid.error == AccumulationDriverError.Uninitialized
  assert driveAccumulation(default(CompletedBlockAccumulation), parameters, policy).error ==
      AccumulationDriverError.InvalidSource
  var short = policy
  short.preparation.selection.executions = ElementLimit(0)
  assert driveAccumulation(root, parameters, short).selectionFailure.error ==
      AccumulationContinuationError.LimitExceeded
  short = policy
  short.preparation.operands.reports = ElementLimit(0)
  assert driveAccumulation(root, parameters, short).inputFailure.operandError ==
      AccumulationOperandError.LimitExceeded
  short = policy
  short.preparation.inputs.services = ElementLimit(0)
  assert driveAccumulation(root, parameters, short).inputFailure.inputError ==
      AccumulationInputError.LimitExceeded
  short = policy
  short.execution.steps = ExecutionStepLimit(0)
  assert driveAccumulation(root, parameters, short).continuationFailure.dispatchFailure.executionError ==
      StepError.StepLimitExceeded
  short = policy
  short.execution.completion.batch.provisions.contexts = ElementLimit(0)
  assert driveAccumulation(root, parameters, short).continuationFailure.continuationFailure.batchFailure.error ==
      AccumulationBatchError.LimitExceeded
  short = policy
  short.preparation.selection.reports = ElementLimit(2)
  assert driveAccumulation(root, parameters, short).reentryPreparationFailure.error ==
      AccumulationReentryError.LimitExceeded
  short = policy
  short.execution.fetch.items = ElementLimit(1)
  assert driveAccumulation(root, parameters, short).reentryExecutionFailure.dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  assert driveAccumulation(root, default(Parameters), policy).continuationFailure.error ==
      AccumulationLaterRunnerError.InvalidParameters
  assert driveAccumulation(initial(provided.source), parameters,
      policy).continuationFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
  # First live reentry succeeds, then a later three-operand group exceeds the same per-entry capture ceiling.
  let lateTail = @[reentryReady(base, 68, [100000'u64, 100000]), reentryReady(base, 69, [0'u64]),
      reentryReady(base, 70, [0'u64])]
  let late = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = lateTail)
  let lateRoot = initial(late.source)
  assert driveAccumulation(lateRoot, parameters, policy).reentryExecutionFailure.dispatchFailure.error ==
      AccumulationDispatchError.LimitExceeded
  assert sameStateSnapshot(fixture.initial.state.snapshot.value, prior)
  var retainedContinuation: StoppedAccumulation
  var retainedReentry: StoppedAccumulation
  block:
    let source = executionFixture(base)
    retainedContinuation = driveAccumulation(runBlockAccumulation(source.round, parameters,
        policy.execution).value,
      parameters, limits(0)).value # Retain terminal history after local parent/round handles die.
  block:
    let source = reentryFixture(base)
    retainedReentry = driveAccumulation(initial(source.source), parameters, limits(
        2)).value # Retain the other stopped alternative independently.
  assert retainedContinuation.stoppedKind == StoppedAccumulationKind.Continuation
  assert retainedReentry.stoppedReentry.executionInfo.value.services == 0
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Full successful histories and depth/late-engine refusals release every temporary machine and backward certificate chain.
    assert driveAccumulation(root, parameters, policy).value.stoppedReentry.executionInfo.value.services == 0
    assert driveAccumulation(simpleInitial, parameters, limits(0)).value.stoppedKind ==
        StoppedAccumulationKind.Continuation
    assert driveAccumulation(root, parameters, limits(2)).error ==
        AccumulationDriverError.DepthExceeded
    assert driveAccumulation(lateRoot, parameters,
        policy).reentryExecutionFailure.dispatchFailure.error ==
        AccumulationDispatchError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_driver", 1000, before, after)
  echo "Bound accumulation driver passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected fixture I/O or exceptions must fail native verification.
except:
  quit(2)
