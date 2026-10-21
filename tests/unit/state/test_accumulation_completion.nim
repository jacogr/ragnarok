# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_completion_arc_release"}

## Genuine stopped driver histories compose complete candidates with manual-root parity and reason-preserving atomic refusal.

import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, report_owned, state_layout, state_trie]
import ../../../src/pvm/machine
import ../../../src/state/[accumulation_completion, accumulation_driver, accumulation_runner,
  accumulation_execution,
  accumulation_round, accumulation_queue, report_admission, block_transition, block_admission,
  accumulation_finalization, accumulation_outputs, accumulation_history, accumulation_ready,
  accumulation_recent, accumulation_times, accumulation_statistics, accumulation_validators,
  accumulation_activity, accumulation_preimages, accumulation_authorization, accumulation_consensus,
  accumulation_block_publication, accumulation_continuation, accumulation_continuation_inputs,
  accumulation_continuation_execution, accumulation_reentry, accumulation_effects, store]
import ../../support/[accumulation_completion_context, accumulation_activity_context,
  accumulation_runner_context, accumulation_reentry_context, accumulation_execution_context,
  pvm_accumulation_context, pvm_accumulation_program, pvm_accumulation_provision, arc_evidence]

# Refuse provider work only after real authenticated source/terminal construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc root(source: PreparedAccumulationValidators): CompletedBlockAccumulation =
  ## Derive the exact admitted initial root from the old manually constructed validator fixture.
  source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value.finalAccumulationOutputs.value.outputsSource.value

proc manualAuthorization(source: PreparedAccumulationValidators,
    limits: AccumulationCompletionLimits): PreparedAccumulationAuthorization =
  ## Existing fixture built all earlier phases independently; compose only the remaining old public APIs.
  let activity = prepareAccumulationActivity(source, limits.composition.activity).value
  let preimages = prepareAccumulationPreimages(activity, limits.composition.preimages).value
  prepareAccumulationAuthorization(preimages, limits.composition.authorization).value

proc manualAuthorization(source: StoppedAccumulation,
    limits: AccumulationCompletionLimits): PreparedAccumulationAuthorization =
  ## Independently spell the public phase chain to check new orchestration on deeper driver histories.
  let finalized = if source.stoppedKind == StoppedAccumulationKind.Continuation:
    prepareFinalAccumulation(source.stoppedContinuation, limits.finalization).value
  else: prepareFinalAccumulation(source.stoppedReentry, limits.finalization).value
  let history = prepareAccumulationHistory(finalized, limits.composition.history).value
  let ready = prepareAccumulationReady(history, limits.composition.ready).value
  let recent = prepareAccumulationRecent(ready, limits.composition.recent).value
  let times = prepareAccumulationTimes(recent, limits.composition.times).value
  let validators = prepareAccumulationValidators(times, limits.composition.validators).value
  manualAuthorization(validators, limits)

proc original(source: CompletedBlockAccumulation): StateStoreSnapshot =
  ## Retain the actual complete original admitted parent without rebuilding equal bytes or taking a partial root.
  source.executionRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState

proc compare(stopped: StoppedAccumulation, expected: PreparedAccumulationConsensus,
    parent: StateStoreSnapshot, limits: AccumulationCompletionLimits): PreparedAccumulationConsensus =
  ## Complete root parity also checks compatibility with unchanged exact-parent, zero-hash publication.
  let finalized = prepareFinalAccumulation(stopped, limits.finalization).value
  failHash(1)
  assert sameStateSnapshot(finalized.finalAccumulationParent.value, parent)
  assert sameStateSnapshot(finalized.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState, parent)
  assert sameStateSnapshot(finalized.finalAccumulationQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState, parent)
  assert hashCalls() == 0 # Original block authority access is immutable and performs no reconstruction.
  failHash(0)
  let prepared = prepareAccumulationComposition(finalized, limits.composition)
  let directHashes = hashCalls()
  assert prepared.error == AccumulationCompletionError.None, $prepared.error
  let actual = prepared.value.accumulationConsensusState.value
  let oracle = expected.accumulationConsensusState.value
  failHash(0)
  let wrapped = prepareStoppedAccumulation(stopped, limits).value.accumulationConsensusState.value
  assert hashCalls() > directHashes, "direct state composition does not repeat C(16) finalization"
  assert array[32, byte](wrapped.commitment.root) == array[32, byte](actual.commitment.root)
  assert array[32, byte](actual.commitment.root) == array[32, byte](oracle.commitment.root)
  assert prepared.value.accumulationConsensusInfo.value.chapters == 7
  var state = forkStateStore(parent).value
  failHash(1)
  let published = publishAccumulationState(state, prepared.value)
  assert published.error == AccumulationPublicationError.None
  assert sameStateSnapshot(state.snapshot.value, actual)
  assert hashCalls() == 0 # Exact prepared snapshot adoption requires no reconstruction or guest replay.
  failHash(0)
  assert not sameStateSnapshot(parent, actual) # Candidate changes are private until explicit publication on the test handle.
  prepared.value

proc scenario(base: OwnedReport, guarantees = 0, available = false, blobs = false,
    provided = false, disputed = false, ticket = false,
        rotated = false): PreparedAccumulationConsensus =
  ## Genuine signed block variants exercise all fixed source roles rather than replacing any candidate chapter.
  let fixture = activityFixture(base, guarantees = guarantees, available = available, blobs = blobs,
    provided = provided, withDispute = disputed, withTicket = ticket, shiftPending = rotated,
    slot = (if rotated: 12'u32 else: 2'u32))
  let initial = root(fixture.source)
  let parent = original(initial)
  let stopped = driveAccumulation(initial, runnerParameters(), completionDriverLimits()).value
  assert stopped.stoppedKind == StoppedAccumulationKind.Continuation
  let limits = completionLimits()
  let expected = prepareAccumulationConsensus(manualAuthorization(fixture.source, limits),
      limits.composition.consensus).value
  compare(stopped, expected, parent, limits)

proc yieldProgram(): seq[byte] =
  ## Literal host-yield/halt code exposes distinct slot/service/input-count commitments across real round history.
  result = @[0'u8]
  for octet in pvmEnvelope([0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 26, 50, 0, 191, 0]):
    result.add(octet) # Preserve complete service metadata and JAM envelope framing.

proc checkStagingPublication(base: OwnedReport) =
  ## Existing state runner/driver/completion APIs preserve a real original-delegator C(7) change through final publication.
  var payload = newSeq[byte](32)
  for index in 0..<32:
    payload[index] = byte(index+1) # The rest of the six-validator raw roster comes from mapped zero padding.
  var code = @[0'u8]
  for octet in guestEnvelope([registerImmediate(7, 196608), registerImmediate(8, 6),
    @[10'u8, 18], @[50'u8, 0]], writable = payload):
    code.add(octet) # Preserve ordinary metadata/envelope framing in the signed parent.
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.firstProgram = code
  executionOptions0.delegator = 42
  executionOptions0.signed.extra = @[activityParentEntry()]
  let fixture = executionFixture(base, executionOptions0)
  let prior = fixture.state.snapshot.value
  var execution = runnerLimits()
  execution.copyBytes = MemoryByteLimit(2016)
  execution.completion.batch.stagingValidators = ElementLimit(6)
  execution.completion.batch.stagingBytes = ByteLimit(4034)
  let initial = runBlockAccumulation(fixture.round, runnerParameters(), execution)
  assert initial.error == AccumulationRunnerError.None
  let stopped = driveAccumulation(initial.value, runnerParameters(), completionDriverLimits()).value
  let limits = completionLimits()
  let finalized = prepareFinalAccumulation(stopped, limits.finalization).value
  let composed = prepareAccumulationComposition(finalized, limits.composition)
  assert composed.error == AccumulationCompletionError.None
  var expected = newSeq[byte](2017)
  expected[0] = 6
  for index in 0..<32:
    expected[index+1] = byte(index+1) # Literal C(7) framing and ordered first record are independent of the production codec.
  let candidate = composed.value.accumulationConsensusState.value
  let key = chapterKey(StateChapter(7))
  assert candidate.lookup(key).value.bytes == expected
  assert prior.lookup(key).value.bytes != expected
  var caller = fixture.state
  failHash(1)
  let published = publishAccumulationState(caller, composed.value)
  assert published.error == AccumulationPublicationError.None and hashCalls() == 0
  failHash(0)
  assert sameStateSnapshot(caller.snapshot.value, candidate)
  assert published.value.lookup(key).value.bytes == expected
  assert sameStateSnapshot(fixture.state.snapshot.value, prior), "signed parent aliases survive private completion and publication"

proc main() {.raises.} =
  # The native runner verifies the static report witness before the test creates real signatures and state commitments.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  checkStagingPublication(base)
  discard scenario(base)
  discard scenario(base, guarantees = 2)
  discard scenario(base, guarantees = 2, available = true, blobs = true, provided = true)
  discard scenario(base, disputed = true)
  discard scenario(base, ticket = true)
  discard scenario(base, rotated = true)
  let limits = completionLimits()
  let fixture = activityFixture(base, guarantees = 2, available = true, blobs = true,
      provided = true)
  let initial = root(fixture.source)
  let parent = original(initial)
  let stopped = driveAccumulation(initial, runnerParameters(), completionDriverLimits()).value
  let missing = default(StoppedAccumulation)
  failHash(1)
  assert prepareAccumulationComposition(default(PreparedFinalAccumulation),
      limits.composition).error == AccumulationCompletionError.InvalidSource
  assert default(PreparedFinalAccumulation).finalAccumulationQueue.error ==
      AccumulationFinalizationError.Uninitialized
  assert default(PreparedFinalAccumulation).finalAccumulationAdmission.error ==
      AccumulationFinalizationError.Uninitialized
  assert default(PreparedFinalAccumulation).finalAccumulationParent.error ==
      AccumulationFinalizationError.Uninitialized
  let invalidFinalized = prepareFinalAccumulation(default(StoppedAccumulation), limits.finalization)
  assert invalidFinalized.error == AccumulationFinalizationError.InvalidSource
  assert hashCalls() == 0 # No default source can trigger finalization, state work or an authenticated parent extraction.
  failHash(0)
  let rejected = prepareStoppedAccumulation(missing, limits)
  assert rejected.error ==
      AccumulationCompletionError.InvalidSource
  let defaultResult = default(AccumulationCompletionResult)
  assert defaultResult.error == AccumulationCompletionError.Uninitialized
  var short = limits
  short.finalization.rounds = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).finalizationFailure.outputError ==
      AccumulationOutputsError.LimitExceeded
  short = limits
  short.composition.history.reports = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).historyFailure.error ==
      AccumulationHistoryError.LimitExceeded
  short = limits
  short.composition.ready.items = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).readyFailure.error ==
      AccumulationReadyError.LimitExceeded
  short = limits
  short.composition.recent.headerBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).recentFailure.error ==
      AccumulationRecentError.LimitExceeded
  short = limits
  short.composition.times.statistics.rounds = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).timesFailure.statisticsError ==
      AccumulationStatisticsError.LimitExceeded
  short = limits
  short.composition.validators.chapterBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).validatorsFailure.error ==
      AccumulationValidatorsError.LimitExceeded
  short = limits
  short.composition.activity.componentBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).activityFailure.error ==
      AccumulationActivityError.LimitExceeded
  short = limits
  short.composition.preimages.items = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).preimagesFailure.error ==
      AccumulationPreimageError.LimitExceeded
  short = limits
  short.composition.authorization.inputBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).authorizationFailure.error ==
      AccumulationAuthorizationError.LimitExceeded
  short = limits
  short.composition.consensus.chapterBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).consensusFailure.error ==
      AccumulationConsensusError.LimitExceeded
  let capped = activityFixture(base, storeWrites = 6)
  let cappedInitial = root(capped.source)
  let cappedParent = original(cappedInitial)
  let cappedStop = driveAccumulation(cappedInitial, runnerParameters(), completionDriverLimits()).value
  assert prepareStoppedAccumulation(cappedStop, limits).consensusFailure.stateError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(original(cappedInitial), cappedParent)
  failHash(0)
  discard manualAuthorization(stopped, limits)
  let hashes = hashCalls() # Exact successful work up to the final fixed consensus overlay, independent of new orchestration.
  failAfter(hashes)
  let backend = prepareStoppedAccumulation(stopped, limits)
  failHash(0)
  assert backend.error == AccumulationCompletionError.ConsensusFailure, $backend.error
  assert backend.consensusFailure.stateError == StateStoreError.BackendFailure
  assert sameStateSnapshot(original(initial), parent)
  # Reentry-backed completion carries every processed queued report and real yield/provide effects through full composition.
  let tail = @[reentryReady(base, 68, [100000'u64, 100000]), reentryReady(base, 69, [100000'u64,
      100000]), reentryReady(base, 70, [0'u64])]
  let repeated = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail,
    extra = @[activityParentEntry()])
  let repeatedRoot = repeated.source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value
  let repeatedStop = driveAccumulation(repeatedRoot, runnerParameters(), completionDriverLimits()).value
  assert repeatedStop.stoppedKind == StoppedAccumulationKind.Reentry
  let repeatedExpected = prepareAccumulationConsensus(manualAuthorization(repeatedStop, limits),
      limits.composition.consensus).value
  discard compare(repeatedStop, repeatedExpected, original(repeatedRoot), limits)
  let yielded = reentryFixture(base, firstProgram = yieldProgram(), secondProgram = yieldProgram(),
      extra = @[activityParentEntry()])
  let yieldedRoot = yielded.source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value
  let yieldedStop = driveAccumulation(yieldedRoot, runnerParameters(), completionDriverLimits()).value
  let yieldedExpected = prepareAccumulationConsensus(manualAuthorization(yieldedStop, limits),
      limits.composition.consensus).value
  discard compare(yieldedStop, yieldedExpected, original(yieldedRoot), limits)
  var retainedFinal: PreparedFinalAccumulation
  block:
    var executionOptions1 = executionFixtureConfig()
    executionOptions1.signed.extra = @[activityParentEntry()]
    let local = executionFixture(base, executionOptions1)
    let ran = runBlockAccumulation(local.round, runnerParameters(), runnerLimits()).value
    let terminal = driveAccumulation(ran, runnerParameters(), completionDriverLimits()).value
    retainedFinal = prepareFinalAccumulation(terminal,
        limits.finalization).value # Final owner alone retains source authority and complete execution state.
  let detached = prepareAccumulationComposition(retainedFinal, limits.composition).value
  var target = forkStateStore(retainedFinal.finalAccumulationParent.value).value
  failHash(1)
  assert publishAccumulationState(target, detached).error == AccumulationPublicationError.None
  assert hashCalls() == 0
  failHash(0)
  var retained: PreparedAccumulationConsensus
  block:
    retained = scenario(base, guarantees = 2, blobs = true) # The final graph and complete map outlive every local driver/fixture handle.
  assert retained.accumulationConsensusInfo.value.chapters == 7
  let reusable = prepareFinalAccumulation(stopped, limits.finalization).value
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Earlier private phase owners and failed late compositions release their entire temporary complete-map graphs.
    assert prepareAccumulationComposition(reusable,
        limits.composition).value.accumulationConsensusInfo.value.chapters == 7
    assert prepareStoppedAccumulation(cappedStop, limits).consensusFailure.stateError ==
        StateStoreError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_completion", 1000, before, after)
  echo "Stopped accumulation completion passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected source I/O or exceptions remain unsuccessful native tests.
except:
  quit(2)
