# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit logical source and frozen resource policy for a genuinely collected current download.
## Qualification preserves existing State provenance and grants no enqueue or adoption authority itself.
import ../state/[parent_logical, current_logical, current_identities, current_request_keys,
    current_refresh_plan, current_logical_refresh, accumulation_current_update]

type
  CurrentLogicalDownloadLimits* = object ## Each existing stage retains an independent caller-supplied budget; no successor-derived defaults.
    identities*: CurrentIdentityLimits
    requests*: CurrentRequestKeyLimits
    reconstruction*: CurrentRefreshLimits
    logical*: CurrentLogicalRefreshLimits
  LogicalDownloadOrigin {.pure.} = enum ## Only constructors select an original configured or previously completed logical source.
    Uninitialized, Configured, Completed
  CurrentLogicalDownloadPolicy* = object ## Immutable retained source and copied policies must be captured before any worker borrows their graph.
    origin: LogicalDownloadOrigin
    parent: SelectedLogicalParent
    prior: CurrentLogicalState
    limits: CurrentLogicalDownloadLimits
  CurrentLogicalDownloadError* {.pure.} = enum ## Exact failed State stages remain distinguishable and contain no successful prefix.
    Uninitialized, None, InvalidPolicy, IdentityFailure, RequestKeyFailure, ReconstructionFailure,
      LogicalPlanFailure, RefreshFailure
  CurrentLogicalDownloadResult* = object ## Only all-stage success exposes the genuine qualified current logical state.
    case status: CurrentLogicalDownloadError
    of None:
      completed: CurrentLogicalState
    of IdentityFailure:
      identityReason: CurrentIdentityResult[PreservedCurrentIdentities]
    of RequestKeyFailure:
      requestReason: CurrentRequestKeyResult[CurrentRequestKeys]
    of ReconstructionFailure:
      reconstructionReason: CurrentRefreshPlanResult[CurrentRefreshPlan]
    of LogicalPlanFailure:
      planReason: LogicalRefreshPlanResult[CurrentLogicalRefreshPlan]
    of RefreshFailure:
      refreshReason: LogicalRefreshResult
    else:
      discard # Default/invalid policies retain no logical state or continuation prefix.

proc initCurrentLogicalDownloadPolicy*(parent: SelectedLogicalParent,
    limits: CurrentLogicalDownloadLimits): CurrentLogicalDownloadPolicy =
  ## Retain explicit configured complete declarations; actual physical/view/Parameters binding is checked against the later genuine update.
  CurrentLogicalDownloadPolicy(origin: LogicalDownloadOrigin.Configured, parent: parent,
      limits: limits)
proc initCurrentLogicalDownloadPolicy*(prior: CurrentLogicalState,
    limits: CurrentLogicalDownloadLimits): CurrentLogicalDownloadPolicy =
  ## Continue from the actual previous completed logical owner after its deferred adoption has been consumed.
  CurrentLogicalDownloadPolicy(origin: LogicalDownloadOrigin.Completed, prior: prior,
      limits: limits)
proc continueCurrentLogicalDownloadPolicy*(policy: CurrentLogicalDownloadPolicy,
    prior: CurrentLogicalState): CurrentLogicalDownloadPolicy =
  ## Advance only the source under the exact previously captured budgets; invalid defaults cannot become enabled policies.
  if policy.origin == LogicalDownloadOrigin.Uninitialized:
    return default(CurrentLogicalDownloadPolicy) # A caller must provision the initial explicit policy independently.
  initCurrentLogicalDownloadPolicy(prior, policy.limits)
func error*(outcome: CurrentLogicalDownloadResult): CurrentLogicalDownloadError =
  ## Observe only the immutable selected stage.
  outcome.status
func value*(outcome: CurrentLogicalDownloadResult): CurrentLogicalState {.inline,
    requires: outcome.status == CurrentLogicalDownloadError.None.} =
  ## Full successful qualification alone exposes a logical owner.
  outcome.completed
func identityFailure*(outcome: CurrentLogicalDownloadResult): CurrentIdentityResult[
    PreservedCurrentIdentities] {.inline, requires: outcome.status ==
        CurrentLogicalDownloadError.IdentityFailure.} =
  ## Preserve the actual original physical/view/Parameters/namespace refusal.
  outcome.identityReason
func requestKeyFailure*(outcome: CurrentLogicalDownloadResult): CurrentRequestKeyResult[
    CurrentRequestKeys] {.inline, requires: outcome.status ==
        CurrentLogicalDownloadError.RequestKeyFailure.} =
  ## Preserve the actual failed request derivation without any partial companion.
  outcome.requestReason
func reconstructionFailure*(outcome: CurrentLogicalDownloadResult): CurrentRefreshPlanResult[
    CurrentRefreshPlan] {.inline, requires: outcome.status ==
        CurrentLogicalDownloadError.ReconstructionFailure.} =
  ## Preserve the exact original reconstruction admission boundary.
  outcome.reconstructionReason
func logicalPlanFailure*(outcome: CurrentLogicalDownloadResult): LogicalRefreshPlanResult[
    CurrentLogicalRefreshPlan] {.inline, requires: outcome.status ==
        CurrentLogicalDownloadError.LogicalPlanFailure.} =
  ## Preserve exact complete qualification policy or component refusal.
  outcome.planReason
func refreshFailure*(outcome: CurrentLogicalDownloadResult): LogicalRefreshResult {.inline,
    requires: outcome.status == CurrentLogicalDownloadError.RefreshFailure.} =
  ## Preserve the actual reconstruction/matching failure without a successful output prefix.
  outcome.refreshReason
proc qualifyCurrentDownload*(policy: CurrentLogicalDownloadPolicy,
    update: PreparedCurrentChainUpdate): CurrentLogicalDownloadResult =
  ## Run only after matching worker collection on the open host gate; every stage consumes its original successful predecessor.
  if policy.origin == LogicalDownloadOrigin.Uninitialized:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.InvalidPolicy)
  let identities = if policy.origin == LogicalDownloadOrigin.Configured:
      preserveCurrentIdentities(policy.parent, update, policy.limits.identities)
    else: preserveCurrentIdentities(policy.prior, update, policy.limits.identities)
  if identities.error != CurrentIdentityError.None:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.IdentityFailure,
        identityReason: identities)
  let keys = captureCurrentRequestKeys(identities.value, policy.limits.requests)
  if keys.error != CurrentRequestKeyError.None:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.RequestKeyFailure,
        requestReason: keys)
  let reconstruction = planCurrentRefresh(keys.value, policy.limits.reconstruction)
  if reconstruction.error != CurrentRefreshPlanError.None:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.ReconstructionFailure,
        reconstructionReason: reconstruction)
  let plan = planCurrentLogicalRefresh(reconstruction.value, policy.limits.logical)
  if plan.error != LogicalRefreshPlanError.None:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.LogicalPlanFailure,
        planReason: plan)
  let refreshed = executeCurrentLogicalRefresh(plan.value)
  if refreshed.error != LogicalRefreshError.None:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.RefreshFailure,
        refreshReason: refreshed)
  CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.None, completed: refreshed.value)
