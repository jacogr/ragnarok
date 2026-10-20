# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind original pools, verified incoming uses and posterior queues to one completed post-preimage source.
## Pure bounded preparation precedes atomic C(1)-only publication on the exact retained complete map.

import ../codec/[bounded, report_owned, state_authorization, state_layout, state_trie, header]
import ./[authorization, block_preimages, recent_history, ready_reconciliation,
  accumulation_publication, block_activity, service_activity, accumulation_statistics,
  accumulation_finalization, accumulation_outputs, accumulation_execution, accumulation_round,
  accumulation_queue, report_admission, guarantee_credentials, block_transition, block_admission, store]

type
  BlockAuthorizationConfig* = object ## Independent guarantee work precedes complete input/output authorization codec budgets.
    guarantees*: ElementLimit
    authorization*: AuthorizationConfig
  BlockAuthorizationInfo* = object ## Copied original profile, incoming-use count and authenticated pool queue position.
    cores*, guarantees*: int
    slot*: AuthorizationSlot
  BlockAuthorizationError* {.pure.} = enum ## Failures retain only the selected typed reason, never partial pool bytes or maps.
    Uninitialized, None, InvalidSource, InvalidConfig, InvalidState, ForeignState,
    LimitExceeded, CodecFailure, TransitionFailure, StateFailure
  AuthorizationData = ref object # Private immutable acyclic context binds canonical output to its exact complete prior.
    source: PublishedBlockPreimages
    prior: StateStoreSnapshot
    entry: StateEntry
    info: BlockAuthorizationInfo
  PreparedBlockAuthorization* = object ## Only source-derived pools/uses/queues authorize this scoped pool update.
    data: nil AuthorizationData
  PublishedData = ref object # Immutable successor and exact preparation outlive caller handles without mutable aliases.
    source: PreparedBlockAuthorization
    state: StateStoreSnapshot
  PublishedBlockAuthorization* = object ## Completed scoped pool publication leaves other block validity gates open.
    data: nil PublishedData
  BlockAuthorizationResult*[T] = object ## Private alternatives protect both selected success and unrelated failure diagnostics.
    case status: BlockAuthorizationError
    of None:
      completed: T # Only selected complete success contains usable state or observations.
    of CodecFailure:
      codecReason: AuthorizationError
    of TransitionFailure:
      transitionReason: AuthorizationTransitionError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No source prefix or default success can escape refusal.

func error*[T](outcome: BlockAuthorizationResult[T]): BlockAuthorizationError =
  ## Inspect the immutable selected reason.
  outcome.status
func value*[T](outcome: BlockAuthorizationResult[T]): T {.inline,
    requires: outcome.status == BlockAuthorizationError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed
func codecError*[T](outcome: BlockAuthorizationResult[T]): AuthorizationError {.inline,
    requires: outcome.status == BlockAuthorizationError.CodecFailure.} =
  ## Inspect only a selected input authorization codec refusal.
  outcome.codecReason
func transitionError*[T](outcome: BlockAuthorizationResult[
    T]): AuthorizationTransitionError {.inline,

requires: outcome.status == BlockAuthorizationError.TransitionFailure.} =
  ## Inspect only a selected complete pool-update refusal.
  outcome.transitionReason
func stateError*[T](outcome: BlockAuthorizationResult[T]): StateStoreError {.inline,
    requires: outcome.status == BlockAuthorizationError.StateFailure.} =
  ## Inspect only a selected complete-map publication refusal.
  outcome.stateReason
proc blockAuthorizationInfo*(plan: PreparedBlockAuthorization): BlockAuthorizationResult[
    BlockAuthorizationInfo] =
  ## Copy the exact profile, incoming guarantee count and authenticated slot.
  let data = plan.data
  if data == nil: return BlockAuthorizationResult[BlockAuthorizationInfo](
      status: BlockAuthorizationError.Uninitialized)
  BlockAuthorizationResult[BlockAuthorizationInfo](status: BlockAuthorizationError.None,
      completed: data.info)
proc blockAuthorizationSource*(plan: PreparedBlockAuthorization): BlockAuthorizationResult[
    PublishedBlockPreimages] =
  ## Retain the exact complete post-preimage source graph independently of caller handles.
  let data = plan.data
  if data == nil: return BlockAuthorizationResult[PublishedBlockPreimages](
      status: BlockAuthorizationError.Uninitialized)
  BlockAuthorizationResult[PublishedBlockPreimages](status: BlockAuthorizationError.None,
      completed: data.source)
proc blockAuthorizationPrior*(plan: PreparedBlockAuthorization): BlockAuthorizationResult[
    StateStoreSnapshot] =
  ## Retain the exact complete post-preimage map required by mutable publication.
  let data = plan.data
  if data == nil: return BlockAuthorizationResult[StateStoreSnapshot](
      status: BlockAuthorizationError.Uninitialized)
  BlockAuthorizationResult[StateStoreSnapshot](status: BlockAuthorizationError.None,
      completed: data.prior)
proc blockAuthorizationEntry*(plan: PreparedBlockAuthorization): BlockAuthorizationResult[StateEntry] =
  ## Copy canonical C(1) bytes without publishing mutable retained storage.
  let data = plan.data
  if data == nil: return BlockAuthorizationResult[StateEntry](
      status: BlockAuthorizationError.Uninitialized)
  BlockAuthorizationResult[StateEntry](status: BlockAuthorizationError.None, completed: data.entry)
proc publishedAuthorizationSource*(plan: PublishedBlockAuthorization): BlockAuthorizationResult[
    PreparedBlockAuthorization] =
  ## Retain the preparation that authorized this complete successor.
  let data = plan.data
  if data == nil: return BlockAuthorizationResult[PreparedBlockAuthorization](
      status: BlockAuthorizationError.Uninitialized)
  BlockAuthorizationResult[PreparedBlockAuthorization](status: BlockAuthorizationError.None,
      completed: data.source)
proc publishedAuthorizationState*(plan: PublishedBlockAuthorization): BlockAuthorizationResult[
    StateStoreSnapshot] =
  ## Retain the complete immutable successor without a mutable store alias.
  let data = plan.data
  if data == nil: return BlockAuthorizationResult[StateStoreSnapshot](
      status: BlockAuthorizationError.Uninitialized)
  BlockAuthorizationResult[StateStoreSnapshot](status: BlockAuthorizationError.None,
      completed: data.state)

proc prepareBlockAuthorization*(source: PublishedBlockPreimages,
    config: BlockAuthorizationConfig): BlockAuthorizationResult[PreparedBlockAuthorization] =
  ## Derive all protocol inputs from the same completed graph; no loose projection, slot or map is accepted.
  template fail(reason: BlockAuthorizationError) =
    ## Drop all private scratch and preserve the original source on refusal.
    return BlockAuthorizationResult[PreparedBlockAuthorization](status: reason)
  let supplied = source.publishedPreimageSource
  if supplied.error != BlockPreimageError.None: fail(BlockAuthorizationError.InvalidSource)
  let recent = supplied.value.blockPreimageSource.value.publishedRecentSource.value
  let ready = recent.recentHistorySource.value.publishedReadySource.value
  let activity = ready.readyReconciliationSource.value.publishedAccumulationSource.value.accumulationPublicationSource.value
  let finalized = activity.blockActivitySource.value.serviceActivitySource.value.statisticsSource.value
  let admission = finalized.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  if uint64(config.authorization.cores) != uint64(stage.blockTransitionProfile.cores): fail(
      BlockAuthorizationError.InvalidConfig)
  let binding = stage.value.admitted
  let credentials = admission.reportCredentials.value
  let count = credentials.verifiedGuaranteeCount.value
  if uint64(count) > uint64(config.guarantees) or count > high(int) div sizeof(CoreAuthorizer):
    fail(BlockAuthorizationError.LimitExceeded) # Bound original guaranteed-use extraction before descriptor allocation.
  let prior = source.publishedPreimageState.value
  let pools = binding.admittedState.lookup(chapterKey(StateChapter(1)))
  let queues = prior.lookup(chapterKey(StateChapter(2)))
  if pools.error != StateStoreError.None or queues.error != StateStoreError.None: fail(
      BlockAuthorizationError.InvalidState)
  if uint64(pools.value.byteLength) > uint64(config.authorization.maxBytes) or uint64(
      queues.value.byteLength) > uint64(config.authorization.maxBytes):
    fail(BlockAuthorizationError.LimitExceeded) # Stored extents precede raw-value copies and decoder materialization.
  let parent = decodeAuthorization(AuthorizationKind.Pools, pools.value.bytes, config.authorization)
  if parent.error != AuthorizationError.None:
    return BlockAuthorizationResult[PreparedBlockAuthorization](
        status: BlockAuthorizationError.CodecFailure, codecReason: parent.error)
  let posterior = decodeAuthorization(AuthorizationKind.Queues, queues.value.bytes,
      config.authorization)
  if posterior.error != AuthorizationError.None:
    return BlockAuthorizationResult[PreparedBlockAuthorization](
        status: BlockAuthorizationError.CodecFailure, codecReason: posterior.error)
  if parent.value.consumed != pools.value.byteLength or posterior.value.consumed !=
      queues.value.byteLength: fail(BlockAuthorizationError.InvalidState)
  var uses = newSeq[CoreAuthorizer](count)
  for index in 0..<count:
    let report = credentials.verifiedGuaranteeAt(index).value.report.ownedReportInfo.value
    uses[index] = CoreAuthorizer(core: AuthorizationCoreIndex(uint64(report.core)),
        authorizer: report.authorizer)
  let slot = AuthorizationSlot(uint32(binding.admittedHeader.headerInfo.value.unsigned.slot))
  let advanced = advanceAuthorization(parent.value.snapshot, posterior.value.snapshot, uses, slot,
      config.authorization)
  if advanced.error != AuthorizationTransitionError.None:
    return BlockAuthorizationResult[PreparedBlockAuthorization](
        status: BlockAuthorizationError.TransitionFailure, transitionReason: advanced.error)
  BlockAuthorizationResult[PreparedBlockAuthorization](status: BlockAuthorizationError.None,
    completed: PreparedBlockAuthorization(data: AuthorizationData(source: source, prior: prior,
      entry: advanced.value, info: BlockAuthorizationInfo(
        cores: parent.value.snapshot.authorizationCores.value,
        guarantees: count, slot: slot))))

proc commit(state: var StateStore, source: PreparedBlockAuthorization): BlockAuthorizationResult[
    PublishedBlockAuthorization] =
  ## Publish only C(1) after exact snapshot identity and complete successful Merklization.
  let data = source.data
  if data == nil: return BlockAuthorizationResult[PublishedBlockAuthorization](
      status: BlockAuthorizationError.InvalidSource)
  let current = state.snapshot
  if current.error != StateStoreError.None: return BlockAuthorizationResult[
      PublishedBlockAuthorization](status: BlockAuthorizationError.InvalidState)
  if not sameStateSnapshot(current.value, data.prior): return BlockAuthorizationResult[
      PublishedBlockAuthorization](status: BlockAuthorizationError.ForeignState)
  var working = forkStateStore(data.prior).value
  let entry = data.entry
  let applied = working.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
      value: entry.value)])
  if applied.error != StateStoreError.None:
    return BlockAuthorizationResult[PublishedBlockAuthorization](
        status: BlockAuthorizationError.StateFailure, stateReason: applied.error)
  state = working # Sole caller publication point follows the successful complete-map apply.
  BlockAuthorizationResult[PublishedBlockAuthorization](status: BlockAuthorizationError.None,
    completed: PublishedBlockAuthorization(data: PublishedData(source: source,
        state: applied.value)))
proc publishBlockAuthorization*(source: PreparedBlockAuthorization): BlockAuthorizationResult[
    PublishedBlockAuthorization] =
  ## Create a private complete successor under the exact retained source's store ceilings.
  let data = source.data
  if data == nil: return BlockAuthorizationResult[PublishedBlockAuthorization](
      status: BlockAuthorizationError.InvalidSource)
  var working = forkStateStore(data.prior).value
  commit(working, source)
proc advanceBlockAuthorization*(state: var StateStore,
    source: PreparedBlockAuthorization): BlockAuthorizationResult[PublishedBlockAuthorization] =
  ## Atomically advance only a caller retaining the exact complete post-preimage snapshot.
  commit(state, source)
