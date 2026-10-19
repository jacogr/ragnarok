# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Finalize a genuine stopped driver result through every supported private accumulation/state chapter phase.
## Returns the existing consensus candidate only after complete success; caller publication remains separate.

import ./[accumulation_driver, accumulation_finalization, accumulation_outputs,
  accumulation_history, accumulation_ready, accumulation_recent, accumulation_times,
  accumulation_validators, accumulation_activity, accumulation_preimages,
  accumulation_authorization, accumulation_consensus]

type
  AccumulationCompletionLimits* = object ## Independent resource ceilings for each existing bounded phase, never replacement source/state values.
    finalization*: AccumulationOutputHistoryLimits ## Finalization preparation policy; underlying nominal domains and limits remain enforced.
    history*: AccumulationHistoryConfig ## History preparation policy; underlying nominal domains and limits remain enforced.
    ready*: AccumulationReadyConfig ## Ready preparation policy; underlying nominal domains and limits remain enforced.
    recent*: AccumulationRecentConfig ## Recent preparation policy; underlying nominal domains and limits remain enforced.
    times*: AccumulationTimesConfig ## Times preparation policy; underlying nominal domains and limits remain enforced.
    validators*: AccumulationValidatorsConfig ## Validators preparation policy; underlying nominal domains and limits remain enforced.
    activity*: AccumulationActivityConfig ## Activity preparation policy; underlying nominal domains and limits remain enforced.
    preimages*: AccumulationPreimageLimits ## Preimages preparation policy; underlying nominal domains and limits remain enforced.
    authorization*: AccumulationAuthorizationLimits ## Authorization preparation policy; underlying nominal domains and limits remain enforced.
    consensus*: AccumulationConsensusLimits ## Consensus preparation policy; underlying nominal domains and limits remain enforced.
  AccumulationCompletionError* {.pure.} = enum ## Defaults/refusals retain no earlier successful phase or partially composed map.
    Uninitialized, None, InvalidSource, FinalizationFailure, HistoryFailure, ReadyFailure,
      RecentFailure, TimesFailure, ValidatorsFailure, ActivityFailure, PreimagesFailure,
      AuthorizationFailure, ConsensusFailure
  AccumulationCompletionResult* = object ## Private alternatives preserve complete failed-parent reasons without exposing successful intermediate owners.
    case status: AccumulationCompletionError
    of None:
      completed: PreparedAccumulationConsensus
    of FinalizationFailure:
      finalizationReason: AccumulationFinalizationResult[
          PreparedFinalAccumulation]      # Invariant: genuinely failed; no success payload exists.
    of HistoryFailure:
      historyReason: AccumulationHistoryResult[PreparedAccumulationHistory] # Invariant: genuinely failed; no success payload exists.
    of ReadyFailure:
      readyReason: AccumulationReadyResult[PreparedAccumulationReady] # Invariant: genuinely failed; no success payload exists.
    of RecentFailure:
      recentReason: AccumulationRecentResult[PreparedAccumulationRecent] # Invariant: genuinely failed; no success payload exists.
    of TimesFailure:
      timesReason: AccumulationTimesResult[PreparedAccumulationTimes] # Invariant: genuinely failed; no success payload exists.
    of ValidatorsFailure:
      validatorsReason: AccumulationValidatorsResult[
          PreparedAccumulationValidators] # Invariant: genuinely failed; no success payload exists.
    of ActivityFailure:
      activityReason: AccumulationActivityResult[PreparedAccumulationActivity] # Invariant: genuinely failed; no success payload exists.
    of PreimagesFailure:
      preimagesReason: AccumulationPreimageResult[
          PreparedAccumulationPreimages]  # Invariant: genuinely failed; no success payload exists.
    of AuthorizationFailure:
      authorizationReason: AccumulationAuthorizationResult[
          PreparedAccumulationAuthorization] # Invariant: genuinely failed; no success payload exists.
    of ConsensusFailure:
      consensusReason: AccumulationConsensusResult[
          PreparedAccumulationConsensus]  # Invariant: genuinely failed; no success payload exists.
    else:
      discard                             # Default/invalid sources carry only their selected reason.

func error*(outcome: AccumulationCompletionResult): AccumulationCompletionError =
  ## Inspect the selected reason without writable variant fields.
  outcome.status
func value*(outcome: AccumulationCompletionResult): PreparedAccumulationConsensus {.inline,
    requires: outcome.status == AccumulationCompletionError.None.} =
  ## Retain the existing full private candidate only after every phase completes.
  outcome.completed
func finalizationFailure*(outcome: AccumulationCompletionResult):
    AccumulationFinalizationResult[PreparedFinalAccumulation] {.inline,
    requires: outcome.status == AccumulationCompletionError.FinalizationFailure.} =
  ## Inspect only the actual failed finalization result and its existing guarded child reasons.
  outcome.finalizationReason
func historyFailure*(outcome: AccumulationCompletionResult):
    AccumulationHistoryResult[PreparedAccumulationHistory] {.inline,
    requires: outcome.status == AccumulationCompletionError.HistoryFailure.} =
  ## Inspect only the actual failed history result and its existing guarded child reasons.
  outcome.historyReason
func readyFailure*(outcome: AccumulationCompletionResult):
    AccumulationReadyResult[PreparedAccumulationReady] {.inline,
    requires: outcome.status == AccumulationCompletionError.ReadyFailure.} =
  ## Inspect only the actual failed ready result and its existing guarded child reasons.
  outcome.readyReason
func recentFailure*(outcome: AccumulationCompletionResult):
    AccumulationRecentResult[PreparedAccumulationRecent] {.inline,
    requires: outcome.status == AccumulationCompletionError.RecentFailure.} =
  ## Inspect only the actual failed recent result and its existing guarded child reasons.
  outcome.recentReason
func timesFailure*(outcome: AccumulationCompletionResult):
    AccumulationTimesResult[PreparedAccumulationTimes] {.inline,
    requires: outcome.status == AccumulationCompletionError.TimesFailure.} =
  ## Inspect only the actual failed times result and its existing guarded child reasons.
  outcome.timesReason
func validatorsFailure*(outcome: AccumulationCompletionResult):
    AccumulationValidatorsResult[PreparedAccumulationValidators] {.inline,
    requires: outcome.status == AccumulationCompletionError.ValidatorsFailure.} =
  ## Inspect only the actual failed validators result and its existing guarded child reasons.
  outcome.validatorsReason
func activityFailure*(outcome: AccumulationCompletionResult):
    AccumulationActivityResult[PreparedAccumulationActivity] {.inline,
    requires: outcome.status == AccumulationCompletionError.ActivityFailure.} =
  ## Inspect only the actual failed activity result and its existing guarded child reasons.
  outcome.activityReason
func preimagesFailure*(outcome: AccumulationCompletionResult):
    AccumulationPreimageResult[PreparedAccumulationPreimages] {.inline,
    requires: outcome.status == AccumulationCompletionError.PreimagesFailure.} =
  ## Inspect only the actual failed preimages result and its existing guarded child reasons.
  outcome.preimagesReason
func authorizationFailure*(outcome: AccumulationCompletionResult):
    AccumulationAuthorizationResult[PreparedAccumulationAuthorization] {.inline,
    requires: outcome.status == AccumulationCompletionError.AuthorizationFailure.} =
  ## Inspect only the actual failed authorization result and its existing guarded child reasons.
  outcome.authorizationReason
func consensusFailure*(outcome: AccumulationCompletionResult):
    AccumulationConsensusResult[PreparedAccumulationConsensus] {.inline,
    requires: outcome.status == AccumulationCompletionError.ConsensusFailure.} =
  ## Inspect only the actual failed consensus result and its existing guarded child reasons.
  outcome.consensusReason

proc prepareStoppedAccumulation*(source: StoppedAccumulation,
    limits: AccumulationCompletionLimits): AccumulationCompletionResult =
  ## Derive every candidate chapter from this stopped source; retain no partial success on any refusal.
  if source.stoppedKind == StoppedAccumulationKind.Uninitialized:
    return AccumulationCompletionResult(status: AccumulationCompletionError.InvalidSource) # Reject before any hashing or phase work.
  let finalization = if source.stoppedKind == StoppedAccumulationKind.Continuation:
    prepareFinalAccumulation(source.stoppedContinuation, limits.finalization)
  else:
    prepareFinalAccumulation(source.stoppedReentry,
        limits.finalization) # Only the genuine stopped reentry alternative remains.
  if finalization.error != AccumulationFinalizationError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.FinalizationFailure,
      finalizationReason: finalization) # Earlier successful phases remain private and are released.
  let history = prepareAccumulationHistory(finalization.value, limits.history)
  if history.error != AccumulationHistoryError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.HistoryFailure,
      historyReason: history) # Earlier successful phases remain private and are released.
  let ready = prepareAccumulationReady(history.value, limits.ready)
  if ready.error != AccumulationReadyError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.ReadyFailure,
      readyReason: ready) # Earlier successful phases remain private and are released.
  let recent = prepareAccumulationRecent(ready.value, limits.recent)
  if recent.error != AccumulationRecentError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.RecentFailure,
      recentReason: recent) # Earlier successful phases remain private and are released.
  let times = prepareAccumulationTimes(recent.value, limits.times)
  if times.error != AccumulationTimesError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.TimesFailure,
      timesReason: times) # Earlier successful phases remain private and are released.
  let validators = prepareAccumulationValidators(times.value, limits.validators)
  if validators.error != AccumulationValidatorsError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.ValidatorsFailure,
      validatorsReason: validators) # Earlier successful phases remain private and are released.
  let activity = prepareAccumulationActivity(validators.value, limits.activity)
  if activity.error != AccumulationActivityError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.ActivityFailure,
      activityReason: activity) # Earlier successful phases remain private and are released.
  let preimages = prepareAccumulationPreimages(activity.value, limits.preimages)
  if preimages.error != AccumulationPreimageError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.PreimagesFailure,
      preimagesReason: preimages) # Earlier successful phases remain private and are released.
  let authorization = prepareAccumulationAuthorization(preimages.value, limits.authorization)
  if authorization.error != AccumulationAuthorizationError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.AuthorizationFailure,
      authorizationReason: authorization) # Earlier successful phases remain private and are released.
  let consensus = prepareAccumulationConsensus(authorization.value, limits.consensus)
  if consensus.error != AccumulationConsensusError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.ConsensusFailure,
      consensusReason: consensus) # Earlier successful phases remain private and are released.
  AccumulationCompletionResult(status: AccumulationCompletionError.None, completed: consensus.value)
