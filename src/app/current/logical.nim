# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Host-side complete logical qualification of genuine collected current preparation.
## The caller keeps every canonical ARC alias stable and touches this API only outside worker leases.
import ../[chain, preparation_worker]
import "./block/input" as current_block_input
import ../collected/update as collected_update
import ../../state/parent/logical as parent_logical
import ../../state/current/[logical as current_logical, identities as current_identities,
    request_keys as current_request_keys]
import ../../state/current/refresh/plan as current_refresh_plan
import ../../state/current/logical/refresh as current_logical_refresh
import ../../state/accumulation/current/update as accumulation_current_update
type
  CollectedLogicalLimits* = object ## Every existing bounded stage keeps its independent caller policy.
    identities*: CurrentIdentityLimits
    requests*: CurrentRequestKeyLimits
    reconstruction*: CurrentRefreshLimits
    qualification*: CurrentLogicalRefreshLimits
  CollectedLogicalError* {.pure.} = enum ## Lifecycle, stale canonical provenance and original typed stage refusals stay distinct.
    Uninitialized, None, NoCompletion, Cancelled, WrongOperation, PreparationFailure,
      StaleUpdate, IdentityFailure, RequestFailure, ReconstructionFailure,
      QualificationFailure, RefreshFailure, InvalidPlan
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
  case captureCollectedUpdate(chain, completion).error
  of CollectedUpdateError.Uninitialized: CollectedLogicalError.Uninitialized
  of CollectedUpdateError.None: CollectedLogicalError.None
  of CollectedUpdateError.NoCompletion: CollectedLogicalError.NoCompletion
  of CollectedUpdateError.Cancelled: CollectedLogicalError.Cancelled
  of CollectedUpdateError.WrongOperation: CollectedLogicalError.WrongOperation
  of CollectedUpdateError.PreparationFailure: CollectedLogicalError.PreparationFailure
  of CollectedUpdateError.StaleUpdate: CollectedLogicalError.StaleUpdate
type
  CollectedLogicalPlan* = object ## The exact genuine collected update and complete identity-preserving preparation cannot be rebound independently.
    initialized: bool
    update: PreparedCurrentChainUpdate
    prepared: CurrentLogicalRefreshPlan
  CollectedLogicalPlanResult* = object ## Failed stages preserve the original guarded CollectedLogicalResult and no executable prefix.
    case successful: bool
    of true: completed: CollectedLogicalPlan
    of false: refused: CollectedLogicalResult
func error*(outcome: CollectedLogicalPlanResult): CollectedLogicalError =
  ## Preserve the original stage vocabulary for both source alternatives and every preparation failure.
  if outcome.successful: CollectedLogicalError.None else: outcome.refused.error
func value*(outcome: CollectedLogicalPlanResult): CollectedLogicalPlan {.inline,
    requires: outcome.successful.} =
  ## Only complete preparation grants an immutable retry plan.
  outcome.completed
func failure*(outcome: CollectedLogicalPlanResult): CollectedLogicalResult {.inline,
    requires: not outcome.successful.} =
  ## Retain original lifecycle, identity, request, reconstruction and qualification failure alternatives.
  outcome.refused
proc refusedPlan(outcome: CollectedLogicalResult): CollectedLogicalPlanResult {.requires: outcome.error !=
    CollectedLogicalError.None.} =
  ## A failed original stage cannot be retagged as an executable plan.
  CollectedLogicalPlanResult(successful: false, refused: outcome)
proc planIdentities(binding: CurrentIdentityResult[PreservedCurrentIdentities],
    limits: CollectedLogicalLimits): CollectedLogicalPlanResult =
  ## Admit and freeze identity/key/reconstruction/current qualification once; actual payload matching remains execution.
  if binding.error != CurrentIdentityError.None:
    return refusedPlan(CollectedLogicalResult(status: CollectedLogicalError.IdentityFailure,
        identityReason: binding))
  let keys = captureCurrentRequestKeys(binding.value, limits.requests)
  if keys.error != CurrentRequestKeyError.None:
    return refusedPlan(CollectedLogicalResult(status: CollectedLogicalError.RequestFailure,
        requestReason: keys))
  let reconstruction = planCurrentRefresh(keys.value, limits.reconstruction)
  if reconstruction.error != CurrentRefreshPlanError.None:
    return refusedPlan(CollectedLogicalResult(status: CollectedLogicalError.ReconstructionFailure,
        reconstructionReason: reconstruction))
  let qualification = planCurrentLogicalRefresh(reconstruction.value, limits.qualification)
  if qualification.error != LogicalRefreshPlanError.None:
    return refusedPlan(CollectedLogicalResult(status: CollectedLogicalError.QualificationFailure,
        qualificationReason: qualification))
  CollectedLogicalPlanResult(successful: true, completed: CollectedLogicalPlan(initialized: true,
    update: binding.value.identityUpdate.value, prepared: qualification.value))
proc planCollectedLogical*(chain: ApplicationChain, completion: PreparationCompletion,
    source: SelectedLogicalParent, limits: CollectedLogicalLimits): CollectedLogicalPlanResult =
  ## Stage only a genuine collected receipt against its still-selected exact canonical parent; no later policy/source substitution is accepted.
  let reason = collectedUpdate(chain, completion)
  if reason == CollectedLogicalError.PreparationFailure:
    return refusedPlan(CollectedLogicalResult(status: CollectedLogicalError.PreparationFailure,
        preparationReason: completion.currentValue))
  if reason != CollectedLogicalError.None:
    return refusedPlan(CollectedLogicalResult(status: reason)) # Refused receipts never touch original source aliases.
  planIdentities(preserveCurrentIdentities(source, completion.currentValue.value,
      limits.identities), limits)
proc planCollectedLogical*(chain: ApplicationChain, completion: PreparationCompletion,
    source: CurrentLogicalState, limits: CollectedLogicalLimits): CollectedLogicalPlanResult =
  ## Stage only a genuine collected receipt against its still-selected exact canonical parent; no later policy/source substitution is accepted.
  let reason = collectedUpdate(chain, completion)
  if reason == CollectedLogicalError.PreparationFailure:
    return refusedPlan(CollectedLogicalResult(status: CollectedLogicalError.PreparationFailure,
        preparationReason: completion.currentValue))
  if reason != CollectedLogicalError.None:
    return refusedPlan(CollectedLogicalResult(status: reason)) # Refused receipts never touch original source aliases.
  planIdentities(preserveCurrentIdentities(source, completion.currentValue.value,
      limits.identities), limits)
proc executeCollectedLogical*(chain: ApplicationChain,
    plan: CollectedLogicalPlan): CollectedLogicalResult =
  ## Matching and raw-key revalidation use frozen preparation only after the exact canonical parent is checked again.
  if not plan.initialized:
    return CollectedLogicalResult(status: CollectedLogicalError.InvalidPlan)
  if not chain.canInstallPrepared(plan.update):
    return CollectedLogicalResult(status: CollectedLogicalError.StaleUpdate)
  let refreshed = executeCurrentLogicalRefresh(plan.prepared)
  if refreshed.error != LogicalRefreshError.None:
    return CollectedLogicalResult(status: CollectedLogicalError.RefreshFailure,
        refreshReason: refreshed)
  CollectedLogicalResult(status: CollectedLogicalError.None, completed: refreshed.value)
proc refreshCollectedLogical*(chain: ApplicationChain, completion: PreparationCompletion,
    source: SelectedLogicalParent, limits: CollectedLogicalLimits): CollectedLogicalResult =
  ## Preserve one-shot behavior through the same staged preparation/execution path and original typed failures.
  let planned = planCollectedLogical(chain, completion, source, limits)
  if planned.error != CollectedLogicalError.None: return planned.failure
  executeCollectedLogical(chain, planned.value)
proc refreshCollectedLogical*(chain: ApplicationChain, completion: PreparationCompletion,
    source: CurrentLogicalState, limits: CollectedLogicalLimits): CollectedLogicalResult =
  ## Preserve one-shot behavior through the same staged preparation/execution path and original typed failures.
  let planned = planCollectedLogical(chain, completion, source, limits)
  if planned.error != CollectedLogicalError.None: return planned.failure
  executeCollectedLogical(chain, planned.value)
