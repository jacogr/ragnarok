# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind complete C13 to genuine current validator/terminal statistics and privately replace the complete activity entry.
## Retain original-parent preimage admission for later integration; no canonical block or nested preimage publication occurs here.

import ../../../codec/[bounded, composite, block_codec, owned, report_owned, assurances]
import ../../../codec/state/[statistics as state_statistics, trie as state_trie]
import ../activity as accumulation_activity
import ./validators as accumulation_current_validators
import ../../validator/projection as validator_projection
import ../../core/service_activity as core_service_activity
import ../../preimages
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
import ../../[availability, store]

type
  CurrentAccumulationActivityError* {.pure.} = enum ## Refusals/defaults never retain a usable source, partial activity entry or successor.
    Uninitialized, None, InvalidSource, LimitExceeded, PreimageFailure, CoreFailure,
    CodecFailure, StateFailure
  CurrentActivityData = ref object # Acyclic retention binds canonical activity and private state to the exact source certificate graph.
    source: PreparedCurrentAccumulationValidators
    preimages: AdmittedPreimages
    info: CoreServiceActivityInfo
    activity: ActivitySnapshot
    entry: StateEntry
    state: StateStoreSnapshot
  PreparedCurrentAccumulationActivity* = object ## Only the source-derived constructor creates a complete private C(13) successor.
    data: nil CurrentActivityData
  CurrentAccumulationActivityResult*[T] = object ## Success and child causes have mutually exclusive guarded payloads.
    case status: CurrentAccumulationActivityError
    of None:
      completed: T
    of PreimageFailure:
      preimageReason: PreimageTransitionError
    of CoreFailure:
      coreReason: CoreServiceActivityError
    of CodecFailure:
      codecReason: ActivityError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # No earlier successful owner survives a refused phase.

func error*[T](outcome: CurrentAccumulationActivityResult[T]): CurrentAccumulationActivityError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status

func value*[T](outcome: CurrentAccumulationActivityResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationActivityError.None.} =
  ## Extract only complete selected success in checked optimized builds.
  outcome.completed

func preimageError*[T](outcome: CurrentAccumulationActivityResult[
    T]): PreimageTransitionError {.inline,

requires: outcome.status == CurrentAccumulationActivityError.PreimageFailure.} =
  ## Inspect only selected original-parent admission refusal.
  outcome.preimageReason

func coreError*[T](outcome: CurrentAccumulationActivityResult[
    T]): CoreServiceActivityError {.inline,

requires: outcome.status == CurrentAccumulationActivityError.CoreFailure.} =
  ## Inspect only selected pure core/service projection refusal.
  outcome.coreReason

func codecError*[T](outcome: CurrentAccumulationActivityResult[T]): ActivityError {.inline,
    requires: outcome.status == CurrentAccumulationActivityError.CodecFailure.} =
  ## Inspect only selected complete C(13) codec refusal.
  outcome.codecReason

func stateError*[T](outcome: CurrentAccumulationActivityResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationActivityError.StateFailure.} =
  ## Inspect only selected private atomic-publication refusal.
  outcome.stateReason

proc currentActivitySource*(plan: PreparedCurrentAccumulationActivity): CurrentAccumulationActivityResult[
    PreparedCurrentAccumulationValidators] =
  ## Retain exact validator, timestamp and completed accumulation provenance.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationValidators](
        status: CurrentAccumulationActivityError.Uninitialized)
  CurrentAccumulationActivityResult[PreparedCurrentAccumulationValidators](
    status: CurrentAccumulationActivityError.None,
    completed: data.source)

proc currentActivityPreimages*(plan: PreparedCurrentAccumulationActivity): CurrentAccumulationActivityResult[
    AdmittedPreimages] =
  ## Retain exact original-parent/body admission for later post-accumulation integration.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationActivityResult[AdmittedPreimages](
        status: CurrentAccumulationActivityError.Uninitialized)
  CurrentAccumulationActivityResult[AdmittedPreimages](
    status: CurrentAccumulationActivityError.None,
    completed: data.preimages)

proc currentActivityInfo*(plan: PreparedCurrentAccumulationActivity): CurrentAccumulationActivityResult[
    CoreServiceActivityInfo] =
  ## Copy source work populations and retained service union cardinality.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationActivityResult[CoreServiceActivityInfo](
        status: CurrentAccumulationActivityError.Uninitialized)
  CurrentAccumulationActivityResult[CoreServiceActivityInfo](
    status: CurrentAccumulationActivityError.None,
    completed: data.info)

proc currentActivitySnapshot*(plan: PreparedCurrentAccumulationActivity): CurrentAccumulationActivityResult[
    ActivitySnapshot] =
  ## Retain immutable complete current/previous/core/service statistics under the source-derived profile.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationActivityResult[ActivitySnapshot](
        status: CurrentAccumulationActivityError.Uninitialized)
  CurrentAccumulationActivityResult[ActivitySnapshot](status: CurrentAccumulationActivityError.None,
    completed: data.activity)

proc currentActivityEntry*(plan: PreparedCurrentAccumulationActivity): CurrentAccumulationActivityResult[StateEntry] =
  ## Copy canonical C(13) bytes independently of retained encoding/snapshot/state storage.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationActivityResult[StateEntry](
        status: CurrentAccumulationActivityError.Uninitialized)
  var bytes = newSeq[byte](data.entry.value.len)
  for index in 0..<bytes.len: bytes[index] = data.entry.value[
      index] # Independent extraction cannot mutate publication.
  CurrentAccumulationActivityResult[StateEntry](status: CurrentAccumulationActivityError.None,
    completed: StateEntry(key: data.entry.key, value: bytes))

proc currentActivityState*(plan: PreparedCurrentAccumulationActivity): CurrentAccumulationActivityResult[
    StateStoreSnapshot] =
  ## Retain the private complete-map successor containing exactly the C(13) replacement.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationActivityResult[StateStoreSnapshot](
        status: CurrentAccumulationActivityError.Uninitialized)
  CurrentAccumulationActivityResult[StateStoreSnapshot](
    status: CurrentAccumulationActivityError.None,
    completed: data.state)

proc prepareCurrentAccumulationActivity*(source: PreparedCurrentAccumulationValidators,
    config: AccumulationActivityConfig): CurrentAccumulationActivityResult[
        PreparedCurrentAccumulationActivity] =
  ## Derive exact block inputs, admit original-parent preimages, assemble all four components and atomically fork C(13).
  template fail(reason: CurrentAccumulationActivityError) =
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](status: reason)
  let retained = source.currentValidatorsSource
  if retained.error != CurrentAccumulationValidatorsError.None:
    fail(CurrentAccumulationActivityError.InvalidSource) # Pure projections and default owners cannot authenticate a source graph.
  let finalized = retained.value.currentRecentSource.value.currentReadySource.value
  let statistics = finalized.currentFinalizationAccounts.value.currentAccountsSource.value
  let sequence = statistics.currentStatisticsSource.value.completedSequenceSource.value
  let admission = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  let body = stage.value.admitted.admittedBlock.blockExtrinsic.value
  let preimageComponent = body.extrinsicPreimages.value
  let assuranceComponent = body.extrinsicAssurances.value
  let preimageMeta = preimageComponent.componentInfo.value
  let assuranceMeta = assuranceComponent.componentInfo.value
  let credentials = admission.reportCredentials.value
  let incomingCount = credentials.verifiedGuaranteeCount.value
  let availableCount = stage.value.availability.availableReportCount
  let accumulationCount = statistics.currentStatisticsInfo.value.services
  if uint64(preimageMeta.consumed) > uint64(config.componentBytes): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if uint64(assuranceMeta.consumed) > uint64(config.componentBytes): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if uint64(preimageMeta.records) > uint64(config.preimages.items): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if uint64(incomingCount) > uint64(config.incoming): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if uint64(availableCount) > uint64(config.available): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if uint64(assuranceMeta.records) > uint64(config.assurances): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if uint64(accumulationCount) > uint64(config.accumulation): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  # Independent native extents precede materializing any descriptor array or body records.
  if incomingCount > high(int) div sizeof(OwnedReport): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if availableCount > high(int) div sizeof(OwnedReport): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if assuranceMeta.records > high(int) div sizeof(Assurance): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if accumulationCount > high(int) div sizeof(ServiceStatisticsEntry): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  let admitted = admitPreimages(stage.value.admitted.admittedState,
    preimageComponent.readPreimages.value,
    config.preimages)
  if admitted.error != PreimageTransitionError.None:
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](
      status: CurrentAccumulationActivityError.PreimageFailure,
      preimageReason: admitted.error) # No provision contribution is accepted before exact original-parent admission.
  let provisionCount = admitted.value.preimageInfo.value.services
  # Bound grouped contribution copies independently of item traversal.
  if uint64(provisionCount) > uint64(config.provisions): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  if provisionCount > high(int) div sizeof(PreimageProvision): fail(
      CurrentAccumulationActivityError.LimitExceeded)
  var incoming = newSeq[OwnedReport](incomingCount)
  for index in 0..<incomingCount: incoming[index] = credentials.verifiedGuaranteeAt(
      index).value.report
  var available = newSeq[OwnedReport](availableCount)
  for index in 0..<availableCount: available[index] = stage.value.availability.availableReportAt(index).value
  var provisions = newSeq[PreimageProvision](provisionCount)
  for index in 0..<provisionCount: provisions[index] = admitted.value.provisionAt(ProvisionIndex(
      uint64(index))).value
  var accumulation = newSeq[ServiceStatisticsEntry](accumulationCount)
  for index in 0..<accumulationCount: accumulation[index] = statistics.currentStatisticsAt(
      StatisticsServiceIndex(uint64(index))).value
  let projected = projectCoreServiceActivity(incoming, available,
    assuranceComponent.readAssurances.value,
    provisions, accumulation, CoreServiceActivityConfig(cores: profile.cores,
      incoming: config.incoming,
      available: config.available, digests: config.digests, assurances: config.assurances,
      provisions: config.provisions, accumulation: config.accumulation, services: config.services))
  if projected.error != CoreServiceActivityError.None:
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](
      status: CurrentAccumulationActivityError.CoreFailure,
      coreReason: projected.error) # Counter/policy refusal never exposes an earlier partial service union.
  let info = projected.value.coreServiceActivityInfo.value
  let validators = source.currentValidatorsProjection.value
  let populations = validators.validatorActivityInfo.value
  var activity = ActivityState(cores: newSeq[CoreActivity](info.cores),
    services: newSeq[ServiceStatisticsEntry](info.services))
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    let count = if epoch == StatisticsEpoch.Current: populations.current else: populations.previous
    activity.validators[epoch] = newSeq[ValidatorActivity](count)
    for index in 0..<count:
      activity.validators[epoch][index] = validators.projectedValidatorAt(epoch,
        StatisticsValidatorIndex(uint64(index))).value # Genuine source bounds both independent populations.
  for index in 0..<info.cores: activity.cores[index] = projected.value.projectedCoreAt(
      StatisticsCoreIndex(uint64(index))).value
  for index in 0..<info.services: activity.services[index] = projected.value.projectedServiceAt(
      StatisticsServiceIndex(uint64(index))).value
  let codec = ActivityConfig(cores: profile.cores, current: ValidatorCount(uint64(
      populations.current)),
    previous: ValidatorCount(uint64(populations.previous)), maxServices: config.services,
    maxBytes: config.activityBytes)
  let encoded = activityStateEntry(activity, codec)
  if encoded.error != ActivityError.None:
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](
      status: CurrentAccumulationActivityError.CodecFailure,
      codecReason: encoded.error) # No private write starts until exact full-component encoding succeeds.
  let decoded = decodeActivityState(encoded.value.value, codec)
  if decoded.error != ActivityError.None:
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](
      status: CurrentAccumulationActivityError.CodecFailure,
      codecReason: decoded.error) # Retain one validated complete immutable activity owner.
  let prior = source.currentValidatorsState.value
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(kind: StateWriteKind.Put, key: encoded.value.key,
    value: encoded.value.value)])
  if applied.error != StateStoreError.None:
    return CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](
      status: CurrentAccumulationActivityError.StateFailure,
      stateReason: applied.error) # Atomic store refusal preserves every original snapshot and admission certificate.
  CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity](
    status: CurrentAccumulationActivityError.None,
    completed: PreparedCurrentAccumulationActivity(data: CurrentActivityData(source: source,
      preimages: admitted.value,
      info: info, activity: decoded.value.snapshot, entry: encoded.value, state: applied.value)))
