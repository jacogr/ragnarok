# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind original preimage admission, posterior fulfillment and authenticated slot to one completed recent-history source.
## Private publication preserves the complete source map; mutable publication requires exact prior snapshot identity.

import ../codec/[bounded, composite, owned, header, block_codec]
import ./[recent_history, ready_reconciliation, accumulation_publication, block_activity,
  service_activity, accumulation_statistics, accumulation_finalization, accumulation_outputs,
  accumulation_execution, accumulation_round, accumulation_queue, report_admission,
  block_transition, block_admission, preimages, store]

type
  BlockPreimageConfig* = object ## Full component capture has its own ceiling before per-blob admission work.
    frameBytes*: ByteLimit
    preimages*: PreimageLimits
  BlockPreimageInfo* = object ## Copied admitted counts include submissions disregarded after accumulation.
    admission*: PreimageAdmissionInfo
    slot*: HeaderSlot
  BlockPreimageError* {.pure.} = enum ## Only complete selected success carries a preparation or successor.
    Uninitialized, None, InvalidSource, InvalidState, ForeignState, LimitExceeded, PreimageFailure
  PreimageData = ref object # Immutable acyclic source, admission and exact posterior base retire together.
    source: PublishedRecentHistory
    admitted: AdmittedPreimages
    prior: StateStoreSnapshot
    info: BlockPreimageInfo
  PreparedBlockPreimages* = object ## Only original-block admission authorizes the retained slot and posterior map.
    data: nil PreimageData
  PublishedData = ref object # Independent successor retains exact original preparation without mutable aliases.
    source: PreparedBlockPreimages
    state: StateStoreSnapshot
  PublishedBlockPreimages* = object ## Completed scoped preimage publication does not certify other block stages.
    data: nil PublishedData
  BlockPreimageResult*[T] = object ## Private tagged alternatives guard values and selected nested reasons.
    case status: BlockPreimageError
    of None:
      completed: T # Only complete success has a usable owner or observation.
    of PreimageFailure:
      preimageReason: PreimageTransitionError
    else:
      discard      # No partial admission, map or root escapes a refusal.

func error*[T](outcome: BlockPreimageResult[T]): BlockPreimageError =
  ## Inspect the selected immutable reason.
  outcome.status
func value*[T](outcome: BlockPreimageResult[T]): T {.inline,
    requires: outcome.status == BlockPreimageError.None.} =
  ## Extract complete selected success under checked optimized contracts.
  outcome.completed
func preimageError*[T](outcome: BlockPreimageResult[T]): PreimageTransitionError {.inline,
    requires: outcome.status == BlockPreimageError.PreimageFailure.} =
  ## Inspect only a selected preimage admission/application refusal.
  outcome.preimageReason
proc blockPreimageInfo*(plan: PreparedBlockPreimages): BlockPreimageResult[BlockPreimageInfo] =
  ## Copy the exact slot and admitted counts without exposing mutable rows.
  let data = plan.data
  if data == nil: return BlockPreimageResult[BlockPreimageInfo](
      status: BlockPreimageError.Uninitialized)
  BlockPreimageResult[BlockPreimageInfo](status: BlockPreimageError.None, completed: data.info)
proc blockPreimageSource*(plan: PreparedBlockPreimages): BlockPreimageResult[
    PublishedRecentHistory] =
  ## Retain the completed source independently of caller handles.
  let data = plan.data
  if data == nil: return BlockPreimageResult[PublishedRecentHistory](
      status: BlockPreimageError.Uninitialized)
  BlockPreimageResult[PublishedRecentHistory](status: BlockPreimageError.None,
      completed: data.source)
proc blockPreimageAdmission*(plan: PreparedBlockPreimages): BlockPreimageResult[AdmittedPreimages] =
  ## Retain original admission for existing source/prior/provision accessors; no mutable certificate storage escapes.
  let data = plan.data
  if data == nil: return BlockPreimageResult[AdmittedPreimages](
      status: BlockPreimageError.Uninitialized)
  BlockPreimageResult[AdmittedPreimages](status: BlockPreimageError.None, completed: data.admitted)
proc blockPreimagePrior*(plan: PreparedBlockPreimages): BlockPreimageResult[StateStoreSnapshot] =
  ## Retain the exact complete post-recent map required by mutable publication.
  let data = plan.data
  if data == nil: return BlockPreimageResult[StateStoreSnapshot](
      status: BlockPreimageError.Uninitialized)
  BlockPreimageResult[StateStoreSnapshot](status: BlockPreimageError.None, completed: data.prior)
proc publishedPreimageSource*(plan: PublishedBlockPreimages): BlockPreimageResult[
    PreparedBlockPreimages] =
  ## Retain the preparation that authorized this immutable successor.
  let data = plan.data
  if data == nil: return BlockPreimageResult[PreparedBlockPreimages](
      status: BlockPreimageError.Uninitialized)
  BlockPreimageResult[PreparedBlockPreimages](status: BlockPreimageError.None,
      completed: data.source)
proc publishedPreimageState*(plan: PublishedBlockPreimages): BlockPreimageResult[
    StateStoreSnapshot] =
  ## Retain the complete immutable successor without a mutable store alias.
  let data = plan.data
  if data == nil: return BlockPreimageResult[StateStoreSnapshot](
      status: BlockPreimageError.Uninitialized)
  BlockPreimageResult[StateStoreSnapshot](status: BlockPreimageError.None, completed: data.state)

proc prepareBlockPreimages*(source: PublishedRecentHistory,
    config: BlockPreimageConfig): BlockPreimageResult[PreparedBlockPreimages] =
  ## Derive original component/prior and authenticated slot from one complete source; refuse before exposing partial admission.
  let recent = source.publishedRecentSource
  if recent.error != RecentHistoryError.None:
    return BlockPreimageResult[PreparedBlockPreimages](status: BlockPreimageError.InvalidSource)
  let ready = recent.value.recentHistorySource.value.publishedReadySource.value
  let activity = ready.readyReconciliationSource.value.publishedAccumulationSource.value.accumulationPublicationSource.value
  let finalized = activity.blockActivitySource.value.serviceActivitySource.value.statisticsSource.value
  let admission = finalized.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
  let binding = admission.reportBlockStage.value.value.admitted
  let component = binding.admittedBlock.blockExtrinsic.value.extrinsicPreimages.value
  let meta = component.componentInfo.value
  if uint64(meta.records) > uint64(config.preimages.items) or uint64(meta.consumed) > uint64(
      config.frameBytes):
    return BlockPreimageResult[PreparedBlockPreimages](
        status: BlockPreimageError.LimitExceeded) # Bound full-frame capture before materialization.
  let captured = component.readPreimages.value
  let admitted = admitPreimages(binding.admittedState, captured, config.preimages)
  if admitted.error != PreimageTransitionError.None:
    return BlockPreimageResult[PreparedBlockPreimages](status: BlockPreimageError.PreimageFailure,
      preimageReason: admitted.error) # Preserve admission, policy and backend reasons without publishing a prefix.
  let info = BlockPreimageInfo(admission: admitted.value.preimageInfo.value,
    slot: binding.admittedHeader.headerInfo.value.unsigned.slot)
  BlockPreimageResult[PreparedBlockPreimages](status: BlockPreimageError.None,
    completed: PreparedBlockPreimages(data: PreimageData(source: source, admitted: admitted.value,
      prior: source.publishedRecentState.value, info: info)))

proc commit(state: var StateStore, source: PreparedBlockPreimages): BlockPreimageResult[
    PublishedBlockPreimages] =
  ## Recheck posterior solicitation privately; update the caller once only after the complete write batch succeeds.
  let data = source.data
  if data == nil: return BlockPreimageResult[PublishedBlockPreimages](
      status: BlockPreimageError.InvalidSource)
  let current = state.snapshot
  if current.error != StateStoreError.None: return BlockPreimageResult[PublishedBlockPreimages](
      status: BlockPreimageError.InvalidState)
  if not sameStateSnapshot(current.value, data.prior):
    return BlockPreimageResult[PublishedBlockPreimages](
        status: BlockPreimageError.ForeignState) # Equal roots do not authorize substituted maps.
  var working = forkStateStore(data.prior).value
  let applied = integratePreimages(working, data.admitted, data.info.slot)
  if applied.error != PreimageTransitionError.None:
    return BlockPreimageResult[PublishedBlockPreimages](status: BlockPreimageError.PreimageFailure,
      preimageReason: applied.error) # Both key preparation and late Merklization failures preserve source/caller state.
  state = working # Sole mutable publication point after successful integration.
  BlockPreimageResult[PublishedBlockPreimages](status: BlockPreimageError.None,
    completed: PublishedBlockPreimages(data: PublishedData(source: source, state: applied.value)))
proc publishBlockPreimages*(source: PreparedBlockPreimages): BlockPreimageResult[
    PublishedBlockPreimages] =
  ## Publish an independent complete successor from the retained exact posterior base.
  let data = source.data
  if data == nil: return BlockPreimageResult[PublishedBlockPreimages](
      status: BlockPreimageError.InvalidSource)
  var working = forkStateStore(data.prior).value
  commit(working, source)
proc advanceBlockPreimages*(state: var StateStore,
    source: PreparedBlockPreimages): BlockPreimageResult[PublishedBlockPreimages] =
  ## Atomically advance only a caller holding the exact post-recent snapshot.
  commit(state, source)
