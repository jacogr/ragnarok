# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit logical source and frozen resource policy for a genuinely collected current download.
## Qualification preserves existing State provenance and grants no enqueue or adoption authority itself.
import ../state/[parent_logical, current_logical, current_identities, current_request_keys,
    current_refresh_plan, current_logical_refresh, accumulation_current_update, logical_continuation]

type
  CurrentLogicalDownloadLimits* = object ## Each existing stage retains an independent caller-supplied budget; no successor-derived defaults.
    identities*: CurrentIdentityLimits
    requests*: CurrentRequestKeyLimits
    reconstruction*: CurrentRefreshLimits
    logical*: CurrentLogicalRefreshLimits
  LogicalDownloadOrigin {.pure.} = enum ## Only constructors select an original configured or previously completed logical source.
    Uninitialized, Configured, Completed
  LogicalDownloadMode {.pure.} = enum ## Explicit constructors choose strict identity preservation or source-bound producer namespace continuation.
    PreserveIdentities, ContinueNamespaces
  CurrentLogicalDownloadPolicy* = object ## Immutable retained source and copied policies must be captured before any worker borrows their graph.
    mode: LogicalDownloadMode
    continuation: LogicalContinuationLimits
    origin: LogicalDownloadOrigin
    parent: SelectedLogicalParent
    prior: CurrentLogicalState
    limits: CurrentLogicalDownloadLimits
  CurrentLogicalDownloadError* {.pure.} = enum ## Exact failed State stages remain distinguishable and contain no successful prefix.
    Uninitialized, None, InvalidPolicy, IdentityFailure, RequestKeyFailure, ReconstructionFailure,
      LogicalPlanFailure, RefreshFailure, ContinuationFailure
  CurrentLogicalDownloadResult* = object ## Only all-stage success exposes the genuine qualified current logical state.
    case status: CurrentLogicalDownloadError
    of None:
      completed: CurrentLogicalState
    of ContinuationFailure:
      continuationReason: LogicalContinuationResult
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
  CurrentLogicalDownloadPolicy(origin: LogicalDownloadOrigin.Configured,
      mode: LogicalDownloadMode.PreserveIdentities, parent: parent, limits: limits)
proc initCurrentLogicalDownloadPolicy*(prior: CurrentLogicalState,
    limits: CurrentLogicalDownloadLimits): CurrentLogicalDownloadPolicy =
  ## Continue from the actual previous completed logical owner after its deferred adoption has been consumed.
  CurrentLogicalDownloadPolicy(origin: LogicalDownloadOrigin.Completed,
      mode: LogicalDownloadMode.PreserveIdentities, prior: prior, limits: limits)
proc initCurrentLogicalDownloadPolicy*(parent: SelectedLogicalParent,
    limits: LogicalContinuationLimits): CurrentLogicalDownloadPolicy =
  ## Explicitly opt into producer namespace evidence while freezing the original configured source and every continuation budget before any native lease.
  CurrentLogicalDownloadPolicy(origin: LogicalDownloadOrigin.Configured,
    mode: LogicalDownloadMode.ContinueNamespaces, parent: parent, continuation: limits)
proc initCurrentLogicalDownloadPolicy*(prior: CurrentLogicalState,
    limits: LogicalContinuationLimits): CurrentLogicalDownloadPolicy =
  ## Reuse a genuinely completed logical owner under explicit bounded namespace continuation; no source-derived resource defaults are inferred.
  CurrentLogicalDownloadPolicy(origin: LogicalDownloadOrigin.Completed,
    mode: LogicalDownloadMode.ContinueNamespaces, prior: prior, continuation: limits)
proc initCurrentLogicalDownloadPolicy*(source: CurrentLogicalDownloadPolicy,
    limits: LogicalContinuationLimits): CurrentLogicalDownloadPolicy =
  ## Explicitly select namespace continuation over an already retained configured/completed source without reopening or substituting its private provenance.
  case source.origin
  of LogicalDownloadOrigin.Configured: initCurrentLogicalDownloadPolicy(source.parent,
      limits) # Keep the exact originally qualified configured owner.
  of LogicalDownloadOrigin.Completed: initCurrentLogicalDownloadPolicy(source.prior,
      limits) # Keep the exact prior completed owner.
  else: default(CurrentLogicalDownloadPolicy) # An invalid source cannot become enabled by supplying budgets.
proc continueCurrentLogicalDownloadPolicy*(policy: CurrentLogicalDownloadPolicy,
    prior: CurrentLogicalState): CurrentLogicalDownloadPolicy =
  ## Advance only the source under the exact previously captured budgets; invalid defaults cannot become enabled policies.
  if policy.origin == LogicalDownloadOrigin.Uninitialized:
    return default(CurrentLogicalDownloadPolicy) # A caller must provision the initial explicit policy independently.
  if policy.mode == LogicalDownloadMode.ContinueNamespaces:
    return initCurrentLogicalDownloadPolicy(prior,
        policy.continuation) # Advance source while retaining the originally frozen mode and budgets.
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
func continuationFailure*(outcome: CurrentLogicalDownloadResult): LogicalContinuationResult {.inline,
    requires: outcome.status == CurrentLogicalDownloadError.ContinuationFailure.} =
  ## Preserve the exact failed namespace stage without exposing any successful prefix.
  outcome.continuationReason
proc qualifyCurrentDownload*(policy: CurrentLogicalDownloadPolicy,
    update: PreparedCurrentChainUpdate): CurrentLogicalDownloadResult =
  ## Run only after matching worker collection on the open host gate; every stage consumes its original successful predecessor.
  if policy.origin == LogicalDownloadOrigin.Uninitialized:
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.InvalidPolicy)
  if policy.mode == LogicalDownloadMode.ContinueNamespaces:
    # The genuine collected update supplies its own producer histories; the policy cannot substitute another update's evidence.
    let continued = if policy.origin == LogicalDownloadOrigin.Configured:
        continueCurrentNamespaces(policy.parent, update, policy.continuation)
      else: continueCurrentNamespaces(policy.prior, update, policy.continuation)
    if continued.error != LogicalContinuationError.None:
      return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.ContinuationFailure,
        continuationReason: continued)
    return CurrentLogicalDownloadResult(status: CurrentLogicalDownloadError.None,
        completed: continued.value)
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
