# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind C13 validator bookkeeping to one genuine current recent-history candidate.
## Derive parent statistics, posterior roster, body observations and reporter identities; retain the unchanged complete map.

import ../../../codec/[bounded, header, assurances, block_codec, owned]
import ../../../codec/state/[safrole as state_safrole, statistics as state_statistics,
    layout as state_layout]
import ../../validator/projection as validator_projection
import ../validators as accumulation_validators
import ./[recent as accumulation_current_recent, ready as accumulation_current_ready,
    finalization as accumulation_current_finalization, accounts as accumulation_current_accounts,
    statistics as accumulation_current_statistics, driver as accumulation_current_driver,
    sequence as accumulation_current_sequence, round as accumulation_current_round]
import "../block/guests" as accumulation_block_guests
import ../[round as accumulation_round, queue as accumulation_queue]
import ../../report/admission as report_admission
import ../../guarantee_credentials
import "../../block/transition" as block_transition
import "../../block/admission" as block_admission
import ../../store

type
  CurrentAccumulationValidatorsError* {.pure.} = enum ## Defaults and failed substeps never contain usable sources or partial observations.
    Uninitialized, None, InvalidSource, MissingState, InvalidState, LimitExceeded,
    RosterFailure, ActivityFailure, ProjectionFailure
  CurrentValidatorsData = ref object # Acyclic source retention authenticates every derived observation and projected tuple.
    source: PreparedCurrentAccumulationRecent
    observations: ValidatorActivityObservations
    projection: ValidatorActivityProjection
  PreparedCurrentAccumulationValidators* = object ## Only the source-derived constructor creates a certified validator candidate.
    data: nil CurrentValidatorsData
  CurrentAccumulationValidatorsResult*[T] = object ## Success and each nested cause have mutually exclusive guarded alternatives.
    case status: CurrentAccumulationValidatorsError
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

func error*[T](outcome: CurrentAccumulationValidatorsResult[
    T]): CurrentAccumulationValidatorsError =
  ## Inspect a reason without granting discriminator mutation.
  outcome.status
func value*[T](outcome: CurrentAccumulationValidatorsResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationValidatorsError.None.} =
  ## Extract only complete selected success under optimized-build contracts.
  outcome.completed
func rosterError*[T](outcome: CurrentAccumulationValidatorsResult[T]): StateComponentError {.inline,
    requires: outcome.status == CurrentAccumulationValidatorsError.RosterFailure.} =
  ## Inspect only a selected roster codec refusal.
  outcome.rosterReason
func activityError*[T](outcome: CurrentAccumulationValidatorsResult[T]): ActivityError {.inline,
    requires: outcome.status == CurrentAccumulationValidatorsError.ActivityFailure.} =
  ## Inspect only a selected parent statistics codec refusal.
  outcome.activityReason
func projectionError*[T](outcome: CurrentAccumulationValidatorsResult[
    T]): ValidatorActivityError {.inline,

requires: outcome.status == CurrentAccumulationValidatorsError.ProjectionFailure.} =
  ## Inspect only a selected pure validator projection refusal.
  outcome.projectionReason

# Copy only a present whole chapter whose byte extent fits the independent policy.
proc chapter(state: StateStoreSnapshot, number: byte, limit: ByteLimit):
    CurrentAccumulationValidatorsResult[seq[byte]] =
  let found = state.lookup(chapterKey(StateChapter(number)))
  if found.error == StateStoreError.MissingKey:
    return CurrentAccumulationValidatorsResult[seq[byte]](
        status: CurrentAccumulationValidatorsError.MissingState)
  if found.error != StateStoreError.None:
    return CurrentAccumulationValidatorsResult[seq[byte]](
        status: CurrentAccumulationValidatorsError.InvalidState)
  if uint64(found.value.byteLength) > uint64(limit):
    return CurrentAccumulationValidatorsResult[seq[byte]](
        status: CurrentAccumulationValidatorsError.LimitExceeded)
  CurrentAccumulationValidatorsResult[seq[byte]](status: CurrentAccumulationValidatorsError.None,
    completed: found.value.bytes)

# Exact roster decoding prevents a suffix or incompatible population from shaping C(13) framing.
proc roster(state: StateStoreSnapshot, number: byte, config: ValidatorStateConfig):
    CurrentAccumulationValidatorsResult[ValidatorStateSnapshot] =
  let bytes = chapter(state, number, config.maxBytes)
  if bytes.error != CurrentAccumulationValidatorsError.None:
    return CurrentAccumulationValidatorsResult[ValidatorStateSnapshot](status: bytes.error)
  let decoded = decodeStateValidators(bytes.value, config)
  if decoded.error != StateComponentError.None:
    return CurrentAccumulationValidatorsResult[ValidatorStateSnapshot](
      status: CurrentAccumulationValidatorsError.RosterFailure, rosterReason: decoded.error)
  if decoded.value.consumed != bytes.value.len:
    return CurrentAccumulationValidatorsResult[ValidatorStateSnapshot](
        status: CurrentAccumulationValidatorsError.InvalidState)
  CurrentAccumulationValidatorsResult[ValidatorStateSnapshot](
    status: CurrentAccumulationValidatorsError.None,
    completed: decoded.value.value)

proc currentValidatorsSource*(plan: PreparedCurrentAccumulationValidators):
    CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationRecent] =
  ## Retain the exact timestamp, recent-history and completed accumulation graph.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationRecent](
        status: CurrentAccumulationValidatorsError.Uninitialized)
  CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationRecent](
    status: CurrentAccumulationValidatorsError.None,
    completed: data.source)

proc currentValidatorsObservations*(plan: PreparedCurrentAccumulationValidators):
    CurrentAccumulationValidatorsResult[ValidatorActivityObservations] =
  ## Copy source-derived header/time and submitted author contributions.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationValidatorsResult[ValidatorActivityObservations](
        status: CurrentAccumulationValidatorsError.Uninitialized)
  CurrentAccumulationValidatorsResult[ValidatorActivityObservations](
    status: CurrentAccumulationValidatorsError.None,
    completed: data.observations)

proc currentValidatorsProjection*(plan: PreparedCurrentAccumulationValidators):
    CurrentAccumulationValidatorsResult[ValidatorActivityProjection] =
  ## Retain immutable fixed validator rows; this pure handle cannot construct a block certificate.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationValidatorsResult[ValidatorActivityProjection](
        status: CurrentAccumulationValidatorsError.Uninitialized)
  CurrentAccumulationValidatorsResult[ValidatorActivityProjection](
    status: CurrentAccumulationValidatorsError.None,
    completed: data.projection)

proc currentValidatorsState*(plan: PreparedCurrentAccumulationValidators):
    CurrentAccumulationValidatorsResult[StateStoreSnapshot] =
  ## Retain the identical complete timestamp map pending combined C(13) publication.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationValidatorsResult[StateStoreSnapshot](
        status: CurrentAccumulationValidatorsError.Uninitialized)
  CurrentAccumulationValidatorsResult[StateStoreSnapshot](
    status: CurrentAccumulationValidatorsError.None,
    completed: data.source.currentRecentState.value)

proc prepareCurrentAccumulationValidators*(source: PreparedCurrentAccumulationRecent,
    config: AccumulationValidatorsConfig): CurrentAccumulationValidatorsResult[
        PreparedCurrentAccumulationValidators] =
  ## Derive every observation from one immutable certificate graph without hashing, verification or publication.
  template fail(reason: CurrentAccumulationValidatorsError) =
    return CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators](status: reason)
  if source.currentRecentSource.error != CurrentAccumulationRecentError.None:
    fail(CurrentAccumulationValidatorsError.InvalidSource) # Only genuine current recent/ready/terminal ownership authenticates these observations.
  let finalized = source.currentRecentSource.value.currentReadySource.value
  let completed = finalized.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let queue = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value
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
    if decoded.error == CurrentAccumulationValidatorsError.RosterFailure:
      return CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators](
        status: CurrentAccumulationValidatorsError.RosterFailure, rosterReason: decoded.rosterError)
    if decoded.error != CurrentAccumulationValidatorsError.None:
      fail(decoded.error) # No activity decoding uses a default roster population.
  let timeBytes = chapter(parent, 11, config.chapterBytes)
  if timeBytes.error != CurrentAccumulationValidatorsError.None: fail(timeBytes.error)
  let time = decodeStateTime(timeBytes.value)
  if time.error != StateComponentError.None or time.value.consumed != timeBytes.value.len:
    fail(CurrentAccumulationValidatorsError.InvalidState) # Whole C(11), not a caller clock or post-Safrole time.
  let activityBytes = chapter(parent, 13, config.chapterBytes)
  if activityBytes.error != CurrentAccumulationValidatorsError.None: fail(activityBytes.error)
  let activity = decodeActivityState(activityBytes.value, ActivityConfig(cores: profile.cores,
    current: ValidatorCount(uint64(active.value.validatorCount.value)),
    previous: ValidatorCount(uint64(previous.value.validatorCount.value)),
    maxServices: config.services, maxBytes: config.chapterBytes))
  if activity.error != ActivityError.None:
    return CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators](
      status: CurrentAccumulationValidatorsError.ActivityFailure, activityReason: activity.error)
  if activity.value.consumed != activityBytes.value.len:
    fail(CurrentAccumulationValidatorsError.InvalidState) # A prefix-valid C(13) cannot authorize a projected successor.
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
    fail(CurrentAccumulationValidatorsError.LimitExceeded) # Materialization cannot bypass count or framed byte policies.
  if uint64(assuranceInfo.records) > uint64(config.projection.assurances) or
      uint64(reporterCount) > uint64(config.projection.reporters):
    fail(CurrentAccumulationValidatorsError.LimitExceeded) # Bound copied index/key observations before extraction.
  if assuranceInfo.records > high(int) div sizeof(Assurance) or
      assuranceInfo.records > high(int) div sizeof(ValidatorIndex) or
      reporterCount > high(int) div sizeof(StateEdKey):
    fail(CurrentAccumulationValidatorsError.LimitExceeded) # Prove native array extents independently of source framing.
  let preimages = preimageComponent.readPreimages.value
  var bytes = 0'u64
  for index in 0..<preimageInfo.records:
    let length = uint64(preimages.ownedBlobLength(index).value)
    if length > uint64(config.preimageBytes)-bytes:
      fail(CurrentAccumulationValidatorsError.LimitExceeded) # Checked sum includes empty and later-unneeded submitted blobs.
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
    return CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators](
      status: CurrentAccumulationValidatorsError.ProjectionFailure,
      projectionReason: projected.error)
  CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators](
    status: CurrentAccumulationValidatorsError.None,
    completed: PreparedCurrentAccumulationValidators(data: CurrentValidatorsData(source: source,
      observations: observations, projection: projected.value)))
