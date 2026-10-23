# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque current updates stage fallible child capture before durable handoff and guarded installation.
import std/assertions
import ./[store, accumulation_current_chain, accumulation_current_consensus,
    accumulation_current_authorization, accumulation_current_preimages,
    accumulation_current_activity, accumulation_current_validators, accumulation_current_recent,
    accumulation_current_ready, accumulation_current_finalization, accumulation_current_accounts,
    accumulation_current_statistics, accumulation_storage_history, service_identity_history,
    request_identity_history, accumulation_current_driver]
import ../codec/bounded
import ../chain/[genesis, provider]

type
  CurrentUpdateData = ref object # Private immutable original/candidate handles and captured child form an acyclic graph.
    parent: StateStoreSnapshot
    prior: ChainView
    state: StateStore
    view: ChainView
    serviceCaptured: bool
    services: ServiceIdentityHistory
    requestCaptured: bool
    requests: RequestIdentityHistory
    storageCaptured: bool
    storage: StorageHistory
    successor: BlockSnapshot
  PreparedCurrentChainUpdate* = object ## Default owners hold no snapshot graph; copies retain one immutable complete preparation.
    data: nil CurrentUpdateData
  CurrentChainPreparationError* {.pure.} = enum ## Failed/default preparation exposes no successful candidate.
    Uninitialized, None, ChainFailure, StorageHistoryFailure, RequestHistoryFailure, ServiceHistoryFailure
  CurrentChainPreparationResult* = object ## Only success carries preparation; only a real failed coordinator carries its guarded child reason.
    case status: CurrentChainPreparationError
    of None:
      completed: PreparedCurrentChainUpdate
    of ChainFailure:
      reason: CurrentAccumulationChainResult
    of StorageHistoryFailure:
      storageReason: StorageHistoryError
    of ServiceHistoryFailure:
      serviceReason: ServiceIdentityHistoryError
    of RequestHistoryFailure:
      requestReason: RequestIdentityHistoryError
    else:
      discard # No successful prefix survives a refused preparation.
func ready*(prepared: PreparedCurrentChainUpdate): bool =
  ## A default owner cannot authorize extraction or installation.
  prepared.data != nil
func error*(outcome: CurrentChainPreparationResult): CurrentChainPreparationError =
  ## Observe only the immutable selected stage.
  outcome.status
func value*(outcome: CurrentChainPreparationResult): PreparedCurrentChainUpdate {.inline,
    requires: outcome.status == CurrentChainPreparationError.None.} =
  ## Only a complete private candidate may leave preparation.
  outcome.completed
func chainFailure*(outcome: CurrentChainPreparationResult): CurrentAccumulationChainResult {.inline,
    requires: outcome.status == CurrentChainPreparationError.ChainFailure.} =
  ## Preserve only the actual failed current coordinator, never its successful prefix.
  outcome.reason
func storageError*(outcome: CurrentChainPreparationResult): StorageHistoryError {.inline,
    requires: outcome.status == CurrentChainPreparationError.StorageHistoryFailure.} =
  ## Preserve the actual optional producer-history capture refusal without exposing its candidate chain.
  outcome.storageReason
func hasStorageHistory*(prepared: PreparedCurrentChainUpdate): bool =
  ## Defaults and explicitly disabled capture grant no selected raw-storage evidence; enabled empty histories remain distinguishable.
  let data = prepared.data
  data != nil and data.storageCaptured
proc currentUpdateStorageHistory*(prepared: PreparedCurrentChainUpdate): StorageHistory {.requires: prepared.hasStorageHistory.} =
  ## Retain only history captured from this exact update's genuine composition source during private preparation.
  let data = prepared.data
  assert data != nil
  data.storage
proc sourceCompletedSequence(source: PreparedCurrentAccumulationConsensus): CompletedCurrentAccumulationSequence =
  ## Successful chain preparation already validated every composition owner; follow that authentic producer chain without rerunning a guest.
  let activity = source.currentConsensusSource.value.currentAuthorizationSource.value.currentPreimagesSource.value
  let finalization = activity.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value
  let completed = finalization.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  completed
proc sourceStorageHistory(source: PreparedCurrentAccumulationConsensus,
    limits: StorageHistoryLimits): StorageHistoryResult[StorageHistory] =
  ## Storage and request projections share the same authentic completed producer boundary.
  captureStorageHistory(sourceCompletedSequence(source), limits)
func requestHistoryError*(outcome: CurrentChainPreparationResult): RequestIdentityHistoryError {.inline,
    requires: outcome.status == CurrentChainPreparationError.RequestHistoryFailure.} =
  ## Preserve the exact selected request retention refusal without exposing a candidate chain.
  outcome.requestReason
func hasRequestHistory*(prepared: PreparedCurrentChainUpdate): bool =
  ## Default/disabled updates grant no request evidence, independently of an enabled empty selected trace.
  let data = prepared.data
  data != nil and data.requestCaptured
proc currentUpdateRequestHistory*(prepared: PreparedCurrentChainUpdate): RequestIdentityHistory {.requires: prepared.hasRequestHistory.} =
  ## Retain only history frozen from this update's own original consensus/composition source during private preparation.
  let data = prepared.data
  assert data != nil
  data.requests
func serviceHistoryError*(outcome: CurrentChainPreparationResult): ServiceIdentityHistoryError {.inline,
    requires: outcome.status == CurrentChainPreparationError.ServiceHistoryFailure.} =
  ## Preserve only the actual selected membership retention refusal.
  outcome.serviceReason
func hasServiceIdentityHistory*(prepared: PreparedCurrentChainUpdate): bool =
  ## Default and disabled updates grant no service identity evidence; enabled empty histories remain distinct.
  let data = prepared.data
  data != nil and data.serviceCaptured
proc currentUpdateServiceIdentityHistory*(prepared: PreparedCurrentChainUpdate): ServiceIdentityHistory {.requires: prepared.hasServiceIdentityHistory.} =
  ## Retain only membership frozen from this exact update's original completed producer.
  let data = prepared.data
  assert data != nil
  data.services
proc prepareCurrentChainUpdate*(state: StateStore, view: ChainView,
    source: PreparedCurrentAccumulationConsensus, headerBytes: ByteLimit,
    storageLimits = default(StorageHistoryLimits),
    requestLimits = default(RequestIdentityHistoryLimits),
    serviceLimits = default(ServiceIdentityHistoryLimits)): CurrentChainPreparationResult =
  ## Run current prepared-state/capture/append once on private handle copies; retain no mutable caller borrow.
  var working = state
  var history = view
  let applied = applyCurrentAccumulationChain(working, history, source, headerBytes)
  if applied.error != CurrentAccumulationChainError.None:
    return CurrentChainPreparationResult(status: CurrentChainPreparationError.ChainFailure,
      reason: applied) # Failed private stages retain no candidate owner or child.
  let captured = uint64(storageLimits.entries) != 0
  var storage = default(StorageHistory)
  if captured:
    # Opt-in retention freezes the actual original completed producer under independent history policies before any candidate escapes.
    let history = sourceStorageHistory(source, storageLimits)
    if history.error != StorageHistoryError.None:
      return CurrentChainPreparationResult(status: CurrentChainPreparationError.StorageHistoryFailure,
          storageReason: history.error) # Private state/view prefixes retire together; neither caller handle was changed.
    storage = history.value
  let capturedRequests = uint64(requestLimits.entries) != 0
  var requests = default(RequestIdentityHistory)
  if capturedRequests:
    # Request retention is independently admitted before any successful private candidate can escape.
    let projected = captureRequestIdentityHistory(sourceCompletedSequence(source), requestLimits)
    if projected.error != RequestIdentityHistoryError.None:
      return CurrentChainPreparationResult(status: CurrentChainPreparationError.RequestHistoryFailure,
          requestReason: projected.error)
    requests = projected.value
  let capturedServices = uint64(serviceLimits.entries) != 0
  var services = default(ServiceIdentityHistory)
  if capturedServices:
    # Admission failure retires every private map/view prefix; neither caller handle has changed.
    let projected = captureServiceIdentityHistory(sourceCompletedSequence(source), serviceLimits)
    if projected.error != ServiceIdentityHistoryError.None:
      return CurrentChainPreparationResult(status: CurrentChainPreparationError.ServiceHistoryFailure,
        serviceReason: projected.error)
    services = projected.value
  CurrentChainPreparationResult(status: CurrentChainPreparationError.None,
    completed: PreparedCurrentChainUpdate(data: CurrentUpdateData(parent: state.snapshot.value,
      prior: view, state: working, view: history, successor: applied.value,
      storageCaptured: captured, storage: storage, requestCaptured: capturedRequests,
      requests: requests, serviceCaptured: capturedServices, services: services)))
proc currentUpdatePriorState*(prepared: PreparedCurrentChainUpdate): StateStoreSnapshot {.requires: prepared.data != nil.} =
  ## Retain the exact original parent; equal roots never substitute another physical owner.
  let data = prepared.data
  assert data != nil # Public readiness and stable retained ownership discharge nullable access.
  data.parent
proc currentUpdatePriorView*(prepared: PreparedCurrentChainUpdate): ChainView {.requires: prepared.data != nil.} =
  ## Copy original ordered history/full Parameters/finality only after caller retention admission.
  let data = prepared.data
  assert data != nil # Stable ownership protects the whole original selected view.
  data.prior
proc currentUpdatePriorViewInfo*(prepared: PreparedCurrentChainUpdate): ChainViewRetentionInfo {.requires: prepared.data != nil.} =
  ## Allocation-free original retention facts let bounded consumers admit before copying view indexes.
  let data = prepared.data
  assert data != nil # No view or block descriptor is copied while inspecting private arrays.
  data.prior.viewRetentionInfo
proc currentUpdateViewInfo*(prepared: PreparedCurrentChainUpdate): ChainViewRetentionInfo {.requires: prepared.data != nil.} =
  ## Allocation-free posterior retention facts precede any heavy current view/child extraction.
  let data = prepared.data
  assert data != nil # Read direct private view structure through one stable immutable owner.
  data.view.viewRetentionInfo
proc currentUpdateState*(prepared: PreparedCurrentChainUpdate): StateStoreSnapshot {.requires: prepared.data != nil.} =
  ## Retain the exact candidate map for durable export, never a writable target handle.
  let data = prepared.data
  assert data != nil # Stable retained ownership discharges nullable field access after the public guard.
  data.successor.stateSnapshot
proc currentUpdateView*(prepared: PreparedCurrentChainUpdate): ChainView {.requires: prepared.data != nil.} =
  ## Retain complete immutable ordered history, parameters and explicit finality for context encoding.
  let data = prepared.data
  assert data != nil # Capture one stable immutable owner for the nullable proof.
  data.view
proc currentUpdateChildContext*(prepared: PreparedCurrentChainUpdate): BlockSnapshotContext {.requires: prepared.data != nil.} =
  ## Copy fixed actual child facts without allocating/copying RPC key/service indexes; safe bounded consumers need no heavy child getter.
  let data = prepared.data
  assert data != nil # Genuine private preparation appends its exact successor as this selected posterior head.
  data.view.bestBlockContext
proc currentUpdateChild*(prepared: PreparedCurrentChainUpdate): BlockSnapshot {.requires: prepared.data != nil.} =
  ## Retain the exact captured child without recapture or hashing.
  let data = prepared.data
  assert data != nil # The checked public precondition and stable local forbid an absent child owner.
  data.successor
proc canInstallCurrentChainUpdate*(state: StateStore, view: ChainView,
    prepared: PreparedCurrentChainUpdate): bool =
  ## Check exact state ownership and complete ordered history/profile/finality before any durable operation.
  let data = prepared.data
  if data == nil: return false # Default handles carry no retained parent or candidate authority.
  let current = state.snapshot
  current.error == StateStoreError.None and sameStateSnapshot(current.value, data.parent) and
    sameChainView(view, data.prior)
proc installCurrentChainUpdate*(state: var StateStore, view: var ChainView,
    prepared: PreparedCurrentChainUpdate) {.requires: canInstallCurrentChainUpdate(state, view, prepared).} =
  ## Single-threaded stable owners cannot change across preflight/durability/install; replacements perform no hashing or callbacks.
  let data = prepared.data
  assert data != nil # Readiness proves the retained data owner before the sole pair of target assignments.
  state = data.state
  view = data.view
