# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assemble complete canonical C(13) from one genuine service activity history and internally derived core/validator owners.
## Hash-free preparation owns the entry; publication applies it only to the exact finalized complete accumulation map.

import ../../codec/bounded
import ../../codec/state/[statistics as state_statistics, trie as state_trie]
import ../service/activity as service_activity
import ../core/activity as core_activity
import ../validator/activity as validator_activity
import ../accumulation/[statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import ./transition as block_transition
import ../store

type
  BlockActivityConfig* = object ## Each producer keeps its policies; complete output has independent service/encoded-byte ceilings.
    core*: CoreActivityConfig
    validators*: ValidatorActivityConfig
    services*: ElementLimit
    maxBytes*: ByteLimit
  BlockActivityError* {.pure.} = enum ## Refusals retain only the selected precise reason, never partial metrics or maps.
    Uninitialized,    ## Default result or opaque owner.
    None,             ## Complete selected success permits extraction.
    InvalidSource,    ## No genuine service activity owner.
    LimitExceeded,    ## Complete output population or native typed extent exceeds policy.
    CoreFailure,      ## Inspect the internally derived core producer's refusal.
    ValidatorFailure, ## Inspect the internally derived validator producer's refusal.
    CodecFailure,     ## Inspect the complete C(13) codec refusal.
    StateFailure      ## Inspect the private publication/store/backend refusal.
  ActivityData = ref object # Acyclic storage owns independent entry bytes and exact producer provenance.
    source: PreparedServiceActivity
    core: PreparedCoreActivity
    validators: PreparedValidatorActivity
    profile: ActivityConfig
    info: ActivityInfo
    entry: StateEntry
  PreparedBlockActivity* = object ## A complete encoded C(13) certificate never claims whole-block validity or publication.
    data: nil ActivityData
  PublishedData = ref object # Exact assembly plus private immutable complete-map successor, without mutable store aliases.
    source: PreparedBlockActivity
    state: StateStoreSnapshot
  PublishedBlockActivity* = object ## Only successful publication retains a source-matched full-state successor.
    data: nil PublishedData
  BlockActivityResult*[T] = object ## Private tagged payloads ensure failed/default extraction is guarded.
    case status: BlockActivityError
    of None:
      completed: T # Only selected complete success contains data.
    of CoreFailure:
      coreReason: CoreActivityError
    of ValidatorFailure:
      validatorReason: ValidatorActivityError
    of CodecFailure:
      codecReason: ActivityError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # Defaults and local refusals cannot fabricate empty output or partial state.

func error*[T](outcome: BlockActivityResult[T]): BlockActivityError =
  ## Inspect the immutable selected outcome.
  outcome.status
func value*[T](outcome: BlockActivityResult[T]): T {.inline,
    requires: outcome.status == BlockActivityError.None.} =
  ## Extract only selected complete success under checked optimized builds.
  outcome.completed
func coreError*[T](outcome: BlockActivityResult[T]): CoreActivityError {.inline,
    requires: outcome.status == BlockActivityError.CoreFailure.} =
  ## Read only the genuine selected core producer failure.
  outcome.coreReason
func validatorError*[T](outcome: BlockActivityResult[T]): ValidatorActivityError {.inline,
    requires: outcome.status == BlockActivityError.ValidatorFailure.} =
  ## Read only the genuine selected validator producer failure.
  outcome.validatorReason
func codecError*[T](outcome: BlockActivityResult[T]): ActivityError {.inline,
    requires: outcome.status == BlockActivityError.CodecFailure.} =
  ## Read only a genuine canonical C(13) encoding refusal.
  outcome.codecReason
func stateError*[T](outcome: BlockActivityResult[T]): StateStoreError {.inline,
    requires: outcome.status == BlockActivityError.StateFailure.} =
  ## Read only the genuine private publication refusal.
  outcome.stateReason

proc blockActivityInfo*(plan: PreparedBlockActivity): BlockActivityResult[ActivityInfo] =
  ## Copy the complete four-component output cardinalities without exposing retained arrays.
  let data = plan.data
  if data == nil: return BlockActivityResult[ActivityInfo](status: BlockActivityError.Uninitialized)
  BlockActivityResult[ActivityInfo](status: BlockActivityError.None, completed: data.info)
proc blockActivityProfile*(plan: PreparedBlockActivity): BlockActivityResult[ActivityConfig] =
  ## Copy the profile derived from source-bound producers for exact output decoding.
  let data = plan.data
  if data == nil: return BlockActivityResult[ActivityConfig](
      status: BlockActivityError.Uninitialized)
  BlockActivityResult[ActivityConfig](status: BlockActivityError.None, completed: data.profile)
proc blockActivitySource*(plan: PreparedBlockActivity): BlockActivityResult[
    PreparedServiceActivity] =
  ## Retain the exact finalized service activity graph after caller handles retire.
  let data = plan.data
  if data == nil: return BlockActivityResult[PreparedServiceActivity](
      status: BlockActivityError.Uninitialized)
  BlockActivityResult[PreparedServiceActivity](status: BlockActivityError.None,
      completed: data.source)
proc blockActivityEntry*(plan: PreparedBlockActivity): BlockActivityResult[StateEntry] =
  ## Copy canonical entry bytes; caller edits cannot alter retained preparation or later publication.
  let data = plan.data
  if data == nil: return BlockActivityResult[StateEntry](status: BlockActivityError.Uninitialized)
  BlockActivityResult[StateEntry](status: BlockActivityError.None, completed: data.entry)
proc publishedActivitySource*(plan: PublishedBlockActivity): BlockActivityResult[
    PreparedBlockActivity] =
  ## Retain the exact opaque preparation that authorized this successor.
  let data = plan.data
  if data == nil: return BlockActivityResult[PreparedBlockActivity](
      status: BlockActivityError.Uninitialized)
  BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.None,
      completed: data.source)
proc publishedActivityState*(plan: PublishedBlockActivity): BlockActivityResult[
    StateStoreSnapshot] =
  ## Retain the complete private successor; no mutable store or partial light mapping escapes.
  let data = plan.data
  if data == nil: return BlockActivityResult[StateStoreSnapshot](
      status: BlockActivityError.Uninitialized)
  BlockActivityResult[StateStoreSnapshot](status: BlockActivityError.None, completed: data.state)

proc prepareBlockActivity*(source: PreparedServiceActivity,
    config: BlockActivityConfig): BlockActivityResult[PreparedBlockActivity] =
  ## Derive every producer from the service owner's original admission; foreign metrics/profile/maps cannot be supplied.
  let serviceInfo = source.serviceActivityInfo
  if serviceInfo.error != ServiceActivityError.None:
    return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.InvalidSource)
  let count = serviceInfo.value.services
  if uint64(count) > uint64(config.services) or count > high(int) div sizeof(ServiceStatisticsEntry):
    return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.LimitExceeded)
  let finalized = source.serviceActivitySource.value.statisticsSource.value
  let initial = finalized.finalAccumulationOutputs.value.outputsSource.value
  let admission = initial.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
  let core = prepareCoreActivity(admission, config.core)
  if core.error != CoreActivityError.None:
    return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.CoreFailure,
      coreReason: core.error) # No partial producer ownership survives a later failure.
  let validators = prepareValidatorActivity(admission, config.validators)
  if validators.error != ValidatorActivityError.None:
    return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.ValidatorFailure,
      validatorReason: validators.error)
  let populations = validators.value.validatorActivityInfo.value.validators
  let cores = core.value.coreActivityInfo.value.cores
  var state = ActivityState()
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    if populations[epoch] > high(int) div sizeof(ValidatorActivity):
      return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.LimitExceeded)
    state.validators[epoch] = newSeq[ValidatorActivity](populations[epoch])
    for index in 0..<populations[epoch]:
      state.validators[epoch][index] = validators.value.validatorActivityAt(epoch,
        StatisticsValidatorIndex(uint64(index))).value # Fixed copies preserve producer epoch ordering exactly.
  if cores > high(int) div sizeof(CoreActivity):
    return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.LimitExceeded)
  state.cores = newSeq[CoreActivity](cores)
  for index in 0..<cores:
    state.cores[index] = core.value.coreActivityAt(StatisticsCoreIndex(uint64(index))).value
  state.services = newSeq[ServiceStatisticsEntry](count)
  for index in 0..<count:
    state.services[index] = source.serviceActivityAt(StatisticsServiceIndex(uint64(index))).value
  let profile = ActivityConfig(cores: CoreCount(uint64(cores)),
    current: ValidatorCount(uint64(populations[StatisticsEpoch.Current])),
    previous: ValidatorCount(uint64(populations[StatisticsEpoch.Previous])),
    maxServices: config.services, maxBytes: config.maxBytes)
  let encoded = activityStateEntry(state, profile)
  if encoded.error != ActivityError.None:
    return BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.CodecFailure,
      codecReason: encoded.error) # Whole-parent sizing and canonical order precede encoded storage allocation.
  BlockActivityResult[PreparedBlockActivity](status: BlockActivityError.None,
    completed: PreparedBlockActivity(data: ActivityData(source: source, core: core.value,
      validators: validators.value, profile: profile, entry: encoded.value,
      info: ActivityInfo(validators: populations, cores: cores, services: count))))

proc publishBlockActivity*(source: PreparedBlockActivity): BlockActivityResult[
    PublishedBlockActivity] =
  ## Atomically apply only C(13) to the exact finalized complete map; inherited policy/backend failure leaves all sources intact.
  let data = source.data
  if data == nil: return BlockActivityResult[PublishedBlockActivity](
      status: BlockActivityError.InvalidSource)
  let prior = data.source.serviceActivitySource.value.statisticsSource.value.finalAccumulationState.value
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(key: data.entry.key, kind: StateWriteKind.Put,
      value: data.entry.value)])
  if applied.error != StateStoreError.None:
    return BlockActivityResult[PublishedBlockActivity](status: BlockActivityError.StateFailure,
      stateReason: applied.error) # No caller handle or partial map is mutated even after a late hash refusal.
  BlockActivityResult[PublishedBlockActivity](status: BlockActivityError.None,
    completed: PublishedBlockActivity(data: PublishedData(source: source, state: applied.value)))
