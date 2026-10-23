# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Host-side complete logical qualification of genuine collected current preparation.
## The caller keeps every canonical ARC alias stable and touches this API only outside worker leases.
import ./[chain, preparation_worker, current_block_input]
import ../state/[parent_logical, current_logical, current_identities, current_request_keys,
    current_refresh_plan, current_logical_refresh, accumulation_current_update]
type
  CollectedLogicalLimits* = object ## Every existing bounded stage keeps its independent caller policy.
    identities*: CurrentIdentityLimits
    requests*: CurrentRequestKeyLimits
    reconstruction*: CurrentRefreshLimits
    qualification*: CurrentLogicalRefreshLimits
  CollectedLogicalError* {.pure.} = enum ## Lifecycle, stale canonical provenance and original typed stage refusals stay distinct.
    Uninitialized, None, NoCompletion, Cancelled, WrongOperation, PreparationFailure,
      StaleUpdate, IdentityFailure, RequestFailure, ReconstructionFailure,
      QualificationFailure, RefreshFailure
  CollectedLogicalResult* = object ## Only whole actual qualification exposes an existing immutable CurrentLogicalState.
    case status: CollectedLogicalError
    of None: completed: CurrentLogicalState
    of PreparationFailure: preparationReason: CurrentBlockInputResult
    of IdentityFailure: identityReason: CurrentIdentityResult[PreservedCurrentIdentities]
    of RequestFailure: requestReason: CurrentRequestKeyResult[CurrentRequestKeys]
    of ReconstructionFailure: reconstructionReason: CurrentRefreshPlanResult[CurrentRefreshPlan]
    of QualificationFailure: qualificationReason: LogicalRefreshPlanResult[CurrentLogicalRefreshPlan]
    of RefreshFailure: refreshReason: LogicalRefreshResult
    else: discard # No lifecycle/default/refused result exposes a successful prefix.
func error*(outcome: CollectedLogicalResult): CollectedLogicalError =
  ## Observe the selected stage without retaining any canonical graph.
  outcome.status
func value*(outcome: CollectedLogicalResult): CurrentLogicalState {.inline,
    requires: outcome.status == CollectedLogicalError.None.} =
  ## Only complete current and original raw-key matching grants logical success.
  outcome.completed
func preparationFailure*(outcome: CollectedLogicalResult): CurrentBlockInputResult {.inline,
    requires: outcome.status == CollectedLogicalError.PreparationFailure.} =
  ## Preserve the genuine receiver failure, including ancestor demand or codec reasons.
  outcome.preparationReason
func identityFailure*(outcome: CollectedLogicalResult): CurrentIdentityResult[
    PreservedCurrentIdentities] {.inline, requires: outcome.status ==
        CollectedLogicalError.IdentityFailure.} =
  ## Preserve exact physical/view mismatch and new or missing identity reasons.
  outcome.identityReason
func requestFailure*(outcome: CollectedLogicalResult): CurrentRequestKeyResult[
    CurrentRequestKeys] {.inline, requires: outcome.status ==
        CollectedLogicalError.RequestFailure.} =
  ## Preserve actual bounded request key derivation or backend failure.
  outcome.requestReason
func reconstructionFailure*(outcome: CollectedLogicalResult): CurrentRefreshPlanResult[
    CurrentRefreshPlan] {.inline, requires: outcome.status ==
        CollectedLogicalError.ReconstructionFailure.} =
  ## Preserve actual value extent and independent reconstruction admission reasons.
  outcome.reconstructionReason
func qualificationFailure*(outcome: CollectedLogicalResult): LogicalRefreshPlanResult[
    CurrentLogicalRefreshPlan] {.inline, requires: outcome.status ==
        CollectedLogicalError.QualificationFailure.} =
  ## Preserve profile/global and complete-map qualification policy failures.
  outcome.qualificationReason
func refreshFailure*(outcome: CollectedLogicalResult): LogicalRefreshResult {.inline,
    requires: outcome.status == CollectedLogicalError.RefreshFailure.} =
  ## Preserve actual reconstruction, complete matching and retained-key capture failures.
  outcome.refreshReason
proc collectedUpdate(chain: ApplicationChain, completion: PreparationCompletion):
    CollectedLogicalError =
  ## Reject non-current receipts before extraction and stale updates before full logical traversal.
  case completion.kind
  of PreparationCompletionKind.Uninitialized: return CollectedLogicalError.NoCompletion
  of PreparationCompletionKind.Cancelled: return CollectedLogicalError.Cancelled
  of PreparationCompletionKind.Completed: return CollectedLogicalError.WrongOperation
  of PreparationCompletionKind.CurrentCompleted:
    let prepared = completion.currentValue
    if prepared.error != CurrentBlockInputError.None:
      return CollectedLogicalError.PreparationFailure # The public caller retains this exact typed failed receiver result.
    if not chain.canInstallPrepared(prepared.value):
      return CollectedLogicalError.StaleUpdate # Exact state, whole view, Parameters and finality bind the original canonical parent.
  CollectedLogicalError.None
proc refreshIdentities(binding: CurrentIdentityResult[PreservedCurrentIdentities],
    limits: CollectedLogicalLimits): CollectedLogicalResult =
  ## Execute one acyclic bounded chain; each failed stage retires its local successful predecessors.
  if binding.error != CurrentIdentityError.None:
    return CollectedLogicalResult(status: CollectedLogicalError.IdentityFailure,
        identityReason: binding)
  let keys = captureCurrentRequestKeys(binding.value, limits.requests)
  if keys.error != CurrentRequestKeyError.None:
    return CollectedLogicalResult(status: CollectedLogicalError.RequestFailure, requestReason: keys)
  let reconstruction = planCurrentRefresh(keys.value, limits.reconstruction)
  if reconstruction.error != CurrentRefreshPlanError.None:
    return CollectedLogicalResult(status: CollectedLogicalError.ReconstructionFailure,
      reconstructionReason: reconstruction)
  let qualification = planCurrentLogicalRefresh(reconstruction.value, limits.qualification)
  if qualification.error != LogicalRefreshPlanError.None:
    return CollectedLogicalResult(status: CollectedLogicalError.QualificationFailure,
      qualificationReason: qualification)
  let refreshed = executeCurrentLogicalRefresh(qualification.value)
  if refreshed.error != LogicalRefreshError.None:
    return CollectedLogicalResult(status: CollectedLogicalError.RefreshFailure,
        refreshReason: refreshed)
  CollectedLogicalResult(status: CollectedLogicalError.None, completed: refreshed.value)
proc refreshCollectedLogical*(chain: ApplicationChain, completion: PreparationCompletion,
    source: SelectedLogicalParent, limits: CollectedLogicalLimits): CollectedLogicalResult =
  ## Qualify only a collected genuine current result against this still-selected canonical parent; installation remains separate.
  let reason = collectedUpdate(chain, completion)
  if reason == CollectedLogicalError.PreparationFailure:
    return CollectedLogicalResult(status: CollectedLogicalError.PreparationFailure,
        preparationReason: completion.currentValue)
  if reason != CollectedLogicalError.None:
    return CollectedLogicalResult(status: reason) # No source alias or logical traversal is needed for a refused receipt.
  refreshIdentities(preserveCurrentIdentities(source, completion.currentValue.value,
      limits.identities), limits)
proc refreshCollectedLogical*(chain: ApplicationChain, completion: PreparationCompletion,
    source: CurrentLogicalState, limits: CollectedLogicalLimits): CollectedLogicalResult =
  ## Qualify only a collected genuine current result against this still-selected canonical parent; installation remains separate.
  let reason = collectedUpdate(chain, completion)
  if reason == CollectedLogicalError.PreparationFailure:
    return CollectedLogicalResult(status: CollectedLogicalError.PreparationFailure,
        preparationReason: completion.currentValue)
  if reason != CollectedLogicalError.None:
    return CollectedLogicalResult(status: reason) # No source alias or logical traversal is needed for a refused receipt.
  refreshIdentities(preserveCurrentIdentities(source, completion.currentValue.value,
      limits.identities), limits)
