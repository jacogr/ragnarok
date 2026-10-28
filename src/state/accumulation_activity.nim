# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind all C(13) observations to one authenticated accumulation candidate and privately replace the complete activity entry.
## Retain original-parent preimage admission for later integration; no canonical block or nested preimage publication occurs here.

import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/block_codec as codec_block_codec
import ../codec/owned as codec_owned
import ../codec/report_owned as codec_report_owned
import ../codec/assurances as codec_assurances
import ../codec/state_statistics as codec_state_statistics
import ../codec/state_trie as codec_state_trie
import ./accumulation_validators as state_accumulation_validators
import ./validator_projection as state_validator_projection
import ./core_service_activity as state_core_service_activity
import ./preimages as state_preimages
import ./accumulation_times as state_accumulation_times
import ./accumulation_statistics as state_accumulation_statistics
import ./accumulation_finalization as state_accumulation_finalization
import ./accumulation_outputs as state_accumulation_outputs
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./guarantee_credentials as state_guarantee_credentials
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./availability as state_availability
import ./store as state_store

type
  AccumulationActivityConfig* = object ## Resource policies only; every chain domain and observation comes from the retained source.
    componentBytes*: ByteLimit ## Per preimage/assurance body component before materialization.
    preimages*: PreimageLimits ## Original-parent admission work and aggregate/per-blob payload bytes.
    incoming*, available*, digests*, assurances*: ElementLimit ## Distinct report roles, incoming digest work and raw votes.
    provisions*, accumulation*, services*: ElementLimit ## Admitted provision groups, certified S rows and final union.
    activityBytes*: ByteLimit  ## Complete canonical C(13) encoding and retained snapshot bytes.
  AccumulationActivityError* {.pure.} = enum ## Refusals/defaults never retain a usable source, partial activity entry or successor.
    Uninitialized, None, InvalidSource, LimitExceeded, PreimageFailure, CoreFailure,
    CodecFailure, StateFailure
  ActivityData = ref object # Acyclic retention binds canonical activity and private state to the exact source certificate graph.
    source: PreparedAccumulationValidators
    preimages: AdmittedPreimages
    info: CoreServiceActivityInfo
    activity: ActivitySnapshot
    entry: StateEntry
    state: StateStoreSnapshot
  PreparedAccumulationActivity* = object ## Only the source-derived constructor creates a complete private C(13) successor.
    data: nil ActivityData
  AccumulationActivityResult*[T] = object ## Success and child causes have mutually exclusive guarded payloads.
    case status: AccumulationActivityError
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

func error*[T](outcome: AccumulationActivityResult[T]): AccumulationActivityError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: AccumulationActivityResult[T]): T {.inline,
    requires: outcome.status == AccumulationActivityError.None.} =
  ## Extract only complete selected success in checked optimized builds.
  outcome.completed
func preimageError*[T](outcome: AccumulationActivityResult[T]): PreimageTransitionError {.inline,
    requires: outcome.status == AccumulationActivityError.PreimageFailure.} =
  ## Inspect only selected original-parent admission refusal.
  outcome.preimageReason
func coreError*[T](outcome: AccumulationActivityResult[T]): CoreServiceActivityError {.inline,
    requires: outcome.status == AccumulationActivityError.CoreFailure.} =
  ## Inspect only selected pure core/service projection refusal.
  outcome.coreReason
func codecError*[T](outcome: AccumulationActivityResult[T]): ActivityError {.inline,
    requires: outcome.status == AccumulationActivityError.CodecFailure.} =
  ## Inspect only selected complete C(13) codec refusal.
  outcome.codecReason
func stateError*[T](outcome: AccumulationActivityResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationActivityError.StateFailure.} =
  ## Inspect only selected private atomic-publication refusal.
  outcome.stateReason

proc accumulationActivitySource*(plan: PreparedAccumulationActivity): AccumulationActivityResult[
    PreparedAccumulationValidators] =
  ## Retain exact validator, timestamp and completed accumulation provenance.
  let data = plan.data
  if data == nil:
    return AccumulationActivityResult[PreparedAccumulationValidators](
        status: AccumulationActivityError.Uninitialized)
  AccumulationActivityResult[PreparedAccumulationValidators](status: AccumulationActivityError.None,
    completed: data.source)

proc accumulationActivityPreimages*(plan: PreparedAccumulationActivity): AccumulationActivityResult[
    AdmittedPreimages] =
  ## Retain exact original-parent/body admission for later post-accumulation integration.
  let data = plan.data
  if data == nil:
    return AccumulationActivityResult[AdmittedPreimages](
        status: AccumulationActivityError.Uninitialized)
  AccumulationActivityResult[AdmittedPreimages](status: AccumulationActivityError.None,
    completed: data.preimages)

proc accumulationActivityInfo*(plan: PreparedAccumulationActivity): AccumulationActivityResult[
    CoreServiceActivityInfo] =
  ## Copy source work populations and retained service union cardinality.
  let data = plan.data
  if data == nil:
    return AccumulationActivityResult[CoreServiceActivityInfo](
        status: AccumulationActivityError.Uninitialized)
  AccumulationActivityResult[CoreServiceActivityInfo](status: AccumulationActivityError.None,
    completed: data.info)

proc accumulationActivitySnapshot*(plan: PreparedAccumulationActivity): AccumulationActivityResult[
    ActivitySnapshot] =
  ## Retain immutable complete current/previous/core/service statistics under the source-derived profile.
  let data = plan.data
  if data == nil:
    return AccumulationActivityResult[ActivitySnapshot](
        status: AccumulationActivityError.Uninitialized)
  AccumulationActivityResult[ActivitySnapshot](status: AccumulationActivityError.None,
    completed: data.activity)

proc accumulationActivityEntry*(plan: PreparedAccumulationActivity): AccumulationActivityResult[StateEntry] =
  ## Copy canonical C(13) bytes independently of retained encoding/snapshot/state storage.
  let data = plan.data
  if data == nil:
    return AccumulationActivityResult[StateEntry](status: AccumulationActivityError.Uninitialized)
  var bytes = newSeq[byte](data.entry.value.len)
  for index in 0..<bytes.len: bytes[index] = data.entry.value[
      index] # Independent extraction cannot mutate publication.
  AccumulationActivityResult[StateEntry](status: AccumulationActivityError.None,
    completed: StateEntry(key: data.entry.key, value: bytes))

proc accumulationActivityState*(plan: PreparedAccumulationActivity): AccumulationActivityResult[
    StateStoreSnapshot] =
  ## Retain the private complete-map successor containing exactly the C(13) replacement.
  let data = plan.data
  if data == nil:
    return AccumulationActivityResult[StateStoreSnapshot](
        status: AccumulationActivityError.Uninitialized)
  AccumulationActivityResult[StateStoreSnapshot](status: AccumulationActivityError.None,
    completed: data.state)

proc prepareAccumulationActivity*(source: PreparedAccumulationValidators,
    config: AccumulationActivityConfig): AccumulationActivityResult[PreparedAccumulationActivity] =
  ## Derive exact block inputs, admit original-parent preimages, assemble all four components and atomically fork C(13).
  template fail(reason: AccumulationActivityError) =
    return AccumulationActivityResult[PreparedAccumulationActivity](status: reason)
  let retained = source.accumulationValidatorsSource
  if retained.error != AccumulationValidatorsError.None:
    fail(AccumulationActivityError.InvalidSource) # Pure projections and default owners cannot authenticate a source graph.
  let statistics = retained.value.accumulationTimesStatistics.value
  let finalized = statistics.statisticsSource.value
  let admission = finalized.finalAccumulationAdmission.value
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
  let accumulationCount = statistics.statisticsInfo.value.services
  if uint64(preimageMeta.consumed) > uint64(config.componentBytes): fail(
      AccumulationActivityError.LimitExceeded)
  if uint64(assuranceMeta.consumed) > uint64(config.componentBytes): fail(
      AccumulationActivityError.LimitExceeded)
  if uint64(preimageMeta.records) > uint64(config.preimages.items): fail(
      AccumulationActivityError.LimitExceeded)
  if uint64(incomingCount) > uint64(config.incoming): fail(AccumulationActivityError.LimitExceeded)
  if uint64(availableCount) > uint64(config.available): fail(
      AccumulationActivityError.LimitExceeded)
  if uint64(assuranceMeta.records) > uint64(config.assurances): fail(
      AccumulationActivityError.LimitExceeded)
  if uint64(accumulationCount) > uint64(config.accumulation): fail(
      AccumulationActivityError.LimitExceeded)
  # Independent native extents precede materializing any descriptor array or body records.
  if incomingCount > high(int) div sizeof(OwnedReport): fail(
      AccumulationActivityError.LimitExceeded)
  if availableCount > high(int) div sizeof(OwnedReport): fail(
      AccumulationActivityError.LimitExceeded)
  if assuranceMeta.records > high(int) div sizeof(Assurance): fail(
      AccumulationActivityError.LimitExceeded)
  if accumulationCount > high(int) div sizeof(ServiceStatisticsEntry): fail(
      AccumulationActivityError.LimitExceeded)
  let admitted = admitPreimages(stage.value.admitted.admittedState,
    preimageComponent.readPreimages.value,
    config.preimages)
  if admitted.error != PreimageTransitionError.None:
    return AccumulationActivityResult[PreparedAccumulationActivity](
      status: AccumulationActivityError.PreimageFailure,
      preimageReason: admitted.error) # No provision contribution is accepted before exact original-parent admission.
  let provisionCount = admitted.value.preimageInfo.value.services
  # Bound grouped contribution copies independently of item traversal.
  if uint64(provisionCount) > uint64(config.provisions): fail(
      AccumulationActivityError.LimitExceeded)
  if provisionCount > high(int) div sizeof(PreimageProvision): fail(
      AccumulationActivityError.LimitExceeded)
  var incoming = newSeq[OwnedReport](incomingCount)
  for index in 0..<incomingCount: incoming[index] = credentials.verifiedGuaranteeAt(
      index).value.report
  var available = newSeq[OwnedReport](availableCount)
  for index in 0..<availableCount: available[index] = stage.value.availability.availableReportAt(index).value
  var provisions = newSeq[PreimageProvision](provisionCount)
  for index in 0..<provisionCount: provisions[index] = admitted.value.provisionAt(ProvisionIndex(
      uint64(index))).value
  var accumulation = newSeq[ServiceStatisticsEntry](accumulationCount)
  for index in 0..<accumulationCount: accumulation[index] = statistics.statisticsAt(
      StatisticsServiceIndex(uint64(index))).value
  let projected = projectCoreServiceActivity(incoming, available,
    assuranceComponent.readAssurances.value,
    provisions, accumulation, CoreServiceActivityConfig(cores: profile.cores,
      incoming: config.incoming,
      available: config.available, digests: config.digests, assurances: config.assurances,
      provisions: config.provisions, accumulation: config.accumulation, services: config.services))
  if projected.error != CoreServiceActivityError.None:
    return AccumulationActivityResult[PreparedAccumulationActivity](
      status: AccumulationActivityError.CoreFailure,
      coreReason: projected.error) # Counter/policy refusal never exposes an earlier partial service union.
  let info = projected.value.coreServiceActivityInfo.value
  let validators = source.accumulationValidatorsProjection.value
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
    return AccumulationActivityResult[PreparedAccumulationActivity](
      status: AccumulationActivityError.CodecFailure,
      codecReason: encoded.error) # No private write starts until exact full-component encoding succeeds.
  let decoded = decodeActivityState(encoded.value.value, codec)
  if decoded.error != ActivityError.None:
    return AccumulationActivityResult[PreparedAccumulationActivity](
      status: AccumulationActivityError.CodecFailure,
      codecReason: decoded.error) # Retain one validated complete immutable activity owner.
  let prior = source.accumulationValidatorsState.value
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(kind: StateWriteKind.Put, key: encoded.value.key,
    value: encoded.value.value)])
  if applied.error != StateStoreError.None:
    return AccumulationActivityResult[PreparedAccumulationActivity](
      status: AccumulationActivityError.StateFailure,
      stateReason: applied.error) # Atomic store refusal preserves every original snapshot and admission certificate.
  AccumulationActivityResult[PreparedAccumulationActivity](status: AccumulationActivityError.None,
    completed: PreparedAccumulationActivity(data: ActivityData(source: source,
      preimages: admitted.value,
      info: info, activity: decoded.value.snapshot, entry: encoded.value, state: applied.value)))
