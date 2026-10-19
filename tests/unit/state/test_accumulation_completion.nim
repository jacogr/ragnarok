# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_completion_arc_release"}

## Genuine stopped driver histories compose complete candidates with manual-root parity and reason-preserving atomic refusal.

import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, report_owned, state_trie]
import ../../../src/state/[accumulation_completion, accumulation_driver, accumulation_execution,
  accumulation_round, accumulation_queue, report_admission, block_transition, block_admission,
  accumulation_finalization, accumulation_outputs, accumulation_history, accumulation_ready,
  accumulation_recent, accumulation_times, accumulation_statistics, accumulation_validators,
  accumulation_activity, accumulation_preimages, accumulation_authorization, accumulation_consensus,
  accumulation_block_publication, accumulation_continuation, accumulation_continuation_inputs,
  accumulation_continuation_execution, accumulation_reentry, accumulation_effects, store]
import ../../support/[accumulation_completion_context, accumulation_activity_context,
  accumulation_runner_context, accumulation_reentry_context, accumulation_execution_context,
  pvm_accumulation_context, pvm_accumulation_provision, arc_evidence]

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
  let activity = prepareAccumulationActivity(source, limits.activity).value
  let preimages = prepareAccumulationPreimages(activity, limits.preimages).value
  prepareAccumulationAuthorization(preimages, limits.authorization).value

proc manualAuthorization(source: StoppedAccumulation,
    limits: AccumulationCompletionLimits): PreparedAccumulationAuthorization =
  ## Independently spell the public phase chain to check new orchestration on deeper driver histories.
  let finalized = if source.stoppedKind == StoppedAccumulationKind.Continuation:
    prepareFinalAccumulation(source.stoppedContinuation, limits.finalization).value
  else: prepareFinalAccumulation(source.stoppedReentry, limits.finalization).value
  let history = prepareAccumulationHistory(finalized, limits.history).value
  let ready = prepareAccumulationReady(history, limits.ready).value
  let recent = prepareAccumulationRecent(ready, limits.recent).value
  let times = prepareAccumulationTimes(recent, limits.times).value
  let validators = prepareAccumulationValidators(times, limits.validators).value
  manualAuthorization(validators, limits)

proc original(source: CompletedBlockAccumulation): StateStoreSnapshot =
  ## Retain the actual complete original admitted parent without rebuilding equal bytes or taking a partial root.
  source.executionRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState

proc compare(stopped: StoppedAccumulation, expected: PreparedAccumulationConsensus,
    parent: StateStoreSnapshot, limits: AccumulationCompletionLimits): PreparedAccumulationConsensus =
  ## Complete root parity also checks compatibility with unchanged exact-parent, zero-hash publication.
  let prepared = prepareStoppedAccumulation(stopped, limits)
  assert prepared.error == AccumulationCompletionError.None, $prepared.error
  let actual = prepared.value.accumulationConsensusState.value
  let oracle = expected.accumulationConsensusState.value
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
      limits.consensus).value
  compare(stopped, expected, parent, limits)

proc yieldProgram(): seq[byte] =
  ## Literal host-yield/halt code exposes distinct slot/service/input-count commitments across real round history.
  result = @[0'u8]
  for octet in pvmEnvelope([0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 26, 50, 0, 191, 0]):
    result.add(octet) # Preserve complete service metadata and JAM envelope framing.

proc main() {.raises.} =
  # The native runner verifies the static report witness before the test creates real signatures and state commitments.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
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
  short.history.reports = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).historyFailure.error ==
      AccumulationHistoryError.LimitExceeded
  short = limits
  short.ready.items = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).readyFailure.error ==
      AccumulationReadyError.LimitExceeded
  short = limits
  short.recent.headerBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).recentFailure.error ==
      AccumulationRecentError.LimitExceeded
  short = limits
  short.times.statistics.rounds = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).timesFailure.statisticsError ==
      AccumulationStatisticsError.LimitExceeded
  short = limits
  short.validators.chapterBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).validatorsFailure.error ==
      AccumulationValidatorsError.LimitExceeded
  short = limits
  short.activity.componentBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).activityFailure.error ==
      AccumulationActivityError.LimitExceeded
  short = limits
  short.preimages.items = ElementLimit(0)
  assert prepareStoppedAccumulation(stopped, short).preimagesFailure.error ==
      AccumulationPreimageError.LimitExceeded
  short = limits
  short.authorization.inputBytes = ByteLimit(0)
  assert prepareStoppedAccumulation(stopped, short).authorizationFailure.error ==
      AccumulationAuthorizationError.LimitExceeded
  short = limits
  short.consensus.chapterBytes = ByteLimit(0)
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
      limits.consensus).value
  discard compare(repeatedStop, repeatedExpected, original(repeatedRoot), limits)
  let yielded = reentryFixture(base, firstProgram = yieldProgram(), secondProgram = yieldProgram(),
      extra = @[activityParentEntry()])
  let yieldedRoot = yielded.source.reentrySource.value.executionContinuation.value.continuationPlan.value.continuationSource.value
  let yieldedStop = driveAccumulation(yieldedRoot, runnerParameters(), completionDriverLimits()).value
  let yieldedExpected = prepareAccumulationConsensus(manualAuthorization(yieldedStop, limits),
      limits.consensus).value
  discard compare(yieldedStop, yieldedExpected, original(yieldedRoot), limits)
  var retained: PreparedAccumulationConsensus
  block:
    retained = scenario(base, guarantees = 2, blobs = true) # The final graph and complete map outlive every local driver/fixture handle.
  assert retained.accumulationConsensusInfo.value.chapters == 7
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Earlier private phase owners and failed late compositions release their entire temporary complete-map graphs.
    assert prepareStoppedAccumulation(stopped, limits).value.accumulationConsensusInfo.value.chapters == 7
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
