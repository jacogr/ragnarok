# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind C(13) validator bookkeeping to one authenticated accumulation timestamp candidate.
## Derive parent statistics, posterior roster, body observations and reporter identities; retain the unchanged complete map.

import ../../codec/[bounded, header, assurances, block_codec, owned]
import ../../codec/state/[safrole as state_safrole, statistics as state_statistics,
    layout as state_layout]
import ../validator/projection as validator_projection
import ./[times as accumulation_times, statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import ../guarantee_credentials
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../store

type
  AccumulationValidatorsConfig* = object ## Resource ceilings only; every chain domain comes from the source certificate.
    chapterBytes*: ByteLimit   ## Per whole parent activity/time/roster and authenticated posterior roster entry.
    validators*, services*: ElementLimit ## Decoded roster population and parent C(13) dictionary work.
    componentBytes*: ByteLimit ## Per selected preimage/assurance body component before copying.
    preimages*: ElementLimit   ## All submitted preimages, independent of later request eligibility.
    preimageBytes*: ByteLimit  ## Aggregate submitted blob bytes, independent of framing overhead.
    projection*: ValidatorActivityLimits ## Retained rows, assurance/reporter work and key comparisons.
  AccumulationValidatorsError* {.pure.} = enum ## Defaults and failed substeps never contain usable sources or partial observations.
    Uninitialized, None, InvalidSource, MissingState, InvalidState, LimitExceeded,
    RosterFailure, ActivityFailure, ProjectionFailure
  ValidatorsData = ref object # Acyclic source retention authenticates every derived observation and projected tuple.
    source: PreparedAccumulationTimes
    observations: ValidatorActivityObservations
    projection: ValidatorActivityProjection
  PreparedAccumulationValidators* = object ## Only the source-derived constructor creates a certified validator candidate.
    data: nil ValidatorsData
  AccumulationValidatorsResult*[T] = object ## Success and each nested cause have mutually exclusive guarded alternatives.
    case status: AccumulationValidatorsError
    of None:
      completed: T
    of RosterFailure:
      rosterReason: StateComponentError
    of ActivityFailure:
      activityReason: ActivityError
    of ProjectionFailure:
      projectionReason: ValidatorActivityError
    else:
      discard # No caller-visible partial epochs, observations or source after refusal.

func error*[T](outcome: AccumulationValidatorsResult[T]): AccumulationValidatorsError =
  ## Inspect a reason without granting discriminator mutation.
  outcome.status
func value*[T](outcome: AccumulationValidatorsResult[T]): T {.inline,
    requires: outcome.status == AccumulationValidatorsError.None.} =
  ## Extract only complete selected success under optimized-build contracts.
  outcome.completed
func rosterError*[T](outcome: AccumulationValidatorsResult[T]): StateComponentError {.inline,
    requires: outcome.status == AccumulationValidatorsError.RosterFailure.} =
  ## Inspect only a selected roster codec refusal.
  outcome.rosterReason
func activityError*[T](outcome: AccumulationValidatorsResult[T]): ActivityError {.inline,
    requires: outcome.status == AccumulationValidatorsError.ActivityFailure.} =
  ## Inspect only a selected parent statistics codec refusal.
  outcome.activityReason
func projectionError*[T](outcome: AccumulationValidatorsResult[T]): ValidatorActivityError {.inline,
    requires: outcome.status == AccumulationValidatorsError.ProjectionFailure.} =
  ## Inspect only a selected pure validator projection refusal.
  outcome.projectionReason

# Copy only a present whole chapter whose byte extent fits the independent policy.
proc chapter(state: StateStoreSnapshot, number: byte, limit: ByteLimit):
    AccumulationValidatorsResult[seq[byte]] =
  let found = state.lookup(chapterKey(StateChapter(number)))
  if found.error == StateStoreError.MissingKey:
    return AccumulationValidatorsResult[seq[byte]](status: AccumulationValidatorsError.MissingState)
  if found.error != StateStoreError.None:
    return AccumulationValidatorsResult[seq[byte]](status: AccumulationValidatorsError.InvalidState)
  if uint64(found.value.byteLength) > uint64(limit):
    return AccumulationValidatorsResult[seq[byte]](
        status: AccumulationValidatorsError.LimitExceeded)
  AccumulationValidatorsResult[seq[byte]](status: AccumulationValidatorsError.None,
    completed: found.value.bytes)

# Exact roster decoding prevents a suffix or incompatible population from shaping C(13) framing.
proc roster(state: StateStoreSnapshot, number: byte, config: ValidatorStateConfig):
    AccumulationValidatorsResult[ValidatorStateSnapshot] =
  let bytes = chapter(state, number, config.maxBytes)
  if bytes.error != AccumulationValidatorsError.None:
    return AccumulationValidatorsResult[ValidatorStateSnapshot](status: bytes.error)
  let decoded = decodeStateValidators(bytes.value, config)
  if decoded.error != StateComponentError.None:
    return AccumulationValidatorsResult[ValidatorStateSnapshot](
      status: AccumulationValidatorsError.RosterFailure, rosterReason: decoded.error)
  if decoded.value.consumed != bytes.value.len:
    return AccumulationValidatorsResult[ValidatorStateSnapshot](
        status: AccumulationValidatorsError.InvalidState)
  AccumulationValidatorsResult[ValidatorStateSnapshot](status: AccumulationValidatorsError.None,
    completed: decoded.value.value)

proc accumulationValidatorsSource*(plan: PreparedAccumulationValidators):
    AccumulationValidatorsResult[PreparedAccumulationTimes] =
  ## Retain the exact timestamp, recent-history and completed accumulation graph.
  let data = plan.data
  if data == nil:
    return AccumulationValidatorsResult[PreparedAccumulationTimes](
        status: AccumulationValidatorsError.Uninitialized)
  AccumulationValidatorsResult[PreparedAccumulationTimes](status: AccumulationValidatorsError.None,
    completed: data.source)

proc accumulationValidatorsObservations*(plan: PreparedAccumulationValidators):
    AccumulationValidatorsResult[ValidatorActivityObservations] =
  ## Copy source-derived header/time and submitted author contributions.
  let data = plan.data
  if data == nil:
    return AccumulationValidatorsResult[ValidatorActivityObservations](
        status: AccumulationValidatorsError.Uninitialized)
  AccumulationValidatorsResult[ValidatorActivityObservations](
    status: AccumulationValidatorsError.None,
    completed: data.observations)

proc accumulationValidatorsProjection*(plan: PreparedAccumulationValidators):
    AccumulationValidatorsResult[ValidatorActivityProjection] =
  ## Retain immutable fixed validator rows; this pure handle cannot construct a block certificate.
  let data = plan.data
  if data == nil:
    return AccumulationValidatorsResult[ValidatorActivityProjection](
        status: AccumulationValidatorsError.Uninitialized)
  AccumulationValidatorsResult[ValidatorActivityProjection](
    status: AccumulationValidatorsError.None,
    completed: data.projection)

proc accumulationValidatorsState*(plan: PreparedAccumulationValidators):
    AccumulationValidatorsResult[StateStoreSnapshot] =
  ## Retain the identical complete timestamp map pending combined C(13) publication.
  let data = plan.data
  if data == nil:
    return AccumulationValidatorsResult[StateStoreSnapshot](
        status: AccumulationValidatorsError.Uninitialized)
  AccumulationValidatorsResult[StateStoreSnapshot](status: AccumulationValidatorsError.None,
    completed: data.source.accumulationTimesState.value)

proc prepareAccumulationValidators*(source: PreparedAccumulationTimes,
    config: AccumulationValidatorsConfig): AccumulationValidatorsResult[
        PreparedAccumulationValidators] =
  ## Derive every observation from one immutable certificate graph without hashing, verification or publication.
  template fail(reason: AccumulationValidatorsError) =
    return AccumulationValidatorsResult[PreparedAccumulationValidators](status: reason)
  let retained = source.accumulationTimesStatistics
  if retained.error != AccumulationTimesError.None:
    fail(AccumulationValidatorsError.InvalidSource) # A detached projection or mutable stage cannot supply block provenance.
  let finalized = retained.value.statisticsSource.value
  let queue = finalized.finalAccumulationQueue.value
  let admission = queue.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  let binding = stage.value.admitted
  let parent = binding.admittedState
  let rosterConfig = ValidatorStateConfig(cores: profile.cores, validators: config.validators,
    maxBytes: config.chapterBytes)
  let active = roster(parent, 8, rosterConfig)
  let previous = roster(parent, 9, rosterConfig)
  let posterior = roster(stage.value.snapshot, 8, rosterConfig)
  for decoded in [active, previous, posterior]:
    if decoded.error == AccumulationValidatorsError.RosterFailure:
      return AccumulationValidatorsResult[PreparedAccumulationValidators](
        status: AccumulationValidatorsError.RosterFailure, rosterReason: decoded.rosterError)
    if decoded.error != AccumulationValidatorsError.None:
      fail(decoded.error) # No activity decoding uses a default roster population.
  let timeBytes = chapter(parent, 11, config.chapterBytes)
  if timeBytes.error != AccumulationValidatorsError.None: fail(timeBytes.error)
  let time = decodeStateTime(timeBytes.value)
  if time.error != StateComponentError.None or time.value.consumed != timeBytes.value.len:
    fail(AccumulationValidatorsError.InvalidState) # Whole C(11), not a caller clock or post-Safrole time.
  let activityBytes = chapter(parent, 13, config.chapterBytes)
  if activityBytes.error != AccumulationValidatorsError.None: fail(activityBytes.error)
  let activity = decodeActivityState(activityBytes.value, ActivityConfig(cores: profile.cores,
    current: ValidatorCount(uint64(active.value.validatorCount.value)),
    previous: ValidatorCount(uint64(previous.value.validatorCount.value)),
    maxServices: config.services, maxBytes: config.chapterBytes))
  if activity.error != ActivityError.None:
    return AccumulationValidatorsResult[PreparedAccumulationValidators](
      status: AccumulationValidatorsError.ActivityFailure, activityReason: activity.error)
  if activity.value.consumed != activityBytes.value.len:
    fail(AccumulationValidatorsError.InvalidState) # A prefix-valid C(13) cannot authorize a projected successor.
  let body = binding.admittedBlock.blockExtrinsic.value
  let preimageComponent = body.extrinsicPreimages.value
  let assuranceComponent = body.extrinsicAssurances.value
  let preimageInfo = preimageComponent.componentInfo.value
  let assuranceInfo = assuranceComponent.componentInfo.value
  let credentials = admission.reportCredentials.value
  let reporterCount = credentials.verifiedReporterCount.value
  if uint64(preimageInfo.records) > uint64(config.preimages) or
      uint64(preimageInfo.consumed) > uint64(config.componentBytes) or
      uint64(assuranceInfo.consumed) > uint64(config.componentBytes):
    fail(AccumulationValidatorsError.LimitExceeded) # Materialization cannot bypass count or framed byte policies.
  if uint64(assuranceInfo.records) > uint64(config.projection.assurances) or
      uint64(reporterCount) > uint64(config.projection.reporters):
    fail(AccumulationValidatorsError.LimitExceeded) # Bound copied index/key observations before extraction.
  if assuranceInfo.records > high(int) div sizeof(Assurance) or
      assuranceInfo.records > high(int) div sizeof(ValidatorIndex) or
      reporterCount > high(int) div sizeof(StateEdKey):
    fail(AccumulationValidatorsError.LimitExceeded) # Prove native array extents independently of source framing.
  let preimages = preimageComponent.readPreimages.value
  var bytes = 0'u64
  for index in 0..<preimageInfo.records:
    let length = uint64(preimages.ownedBlobLength(index).value)
    if length > uint64(config.preimageBytes)-bytes:
      fail(AccumulationValidatorsError.LimitExceeded) # Checked sum includes empty and later-unneeded submitted blobs.
    bytes += length
  let assurances = assuranceComponent.readAssurances.value
  var indices = newSeq[ValidatorIndex](assurances.len)
  for index in 0..<indices.len: indices[index] = assurances[
      index].validator # Already authenticated parent positions.
  var reporters = newSeq[StateEdKey](reporterCount)
  for index in 0..<reporterCount: reporters[index] = credentials.verifiedReporterAt(
      index).value # Distinct certified keys, not credential occurrences.
  let header = binding.admittedHeader.headerInfo.value.unsigned
  let observations = ValidatorActivityObservations(parentSlot: time.value.value,
    slot: StateTime(uint32(header.slot)), epochSlots: profile.epochSlots, author: header.author,
    tickets: ActivityNatural(uint64(body.extrinsicTickets.value.componentInfo.value.records)),
    preimages: ActivityNatural(uint64(preimageInfo.records)), preimageBytes: ActivityNatural(bytes))
  let projected = projectValidatorActivity(activity.value.snapshot, posterior.value, observations,
    indices, reporters, config.projection)
  if projected.error != ValidatorActivityError.None:
    return AccumulationValidatorsResult[PreparedAccumulationValidators](
      status: AccumulationValidatorsError.ProjectionFailure, projectionReason: projected.error)
  AccumulationValidatorsResult[PreparedAccumulationValidators](
    status: AccumulationValidatorsError.None,
    completed: PreparedAccumulationValidators(data: ValidatorsData(source: source,
      observations: observations, projection: projected.value)))
