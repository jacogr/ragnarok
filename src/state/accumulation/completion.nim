# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compose state phases from one immutable finalized execution successor.
## The stopped convenience entry finalizes once; caller publication remains separate after complete state success.

import ./[driver as accumulation_driver, finalization as accumulation_finalization,
    outputs as accumulation_outputs, history as accumulation_history, ready as accumulation_ready,
    recent as accumulation_recent, times as accumulation_times,
    validators as accumulation_validators, activity as accumulation_activity,
    preimages as accumulation_preimages, authorization as accumulation_authorization,
    consensus as accumulation_consensus]

type
  AccumulationCompositionLimits* = object ## State-only phase ceilings; finalized execution and original block authority are supplied by one immutable successor.
    history*: AccumulationHistoryConfig ## History preparation policy; underlying nominal domains and limits remain enforced.
    ready*: AccumulationReadyConfig ## Ready preparation policy; underlying nominal domains and limits remain enforced.
    recent*: AccumulationRecentConfig ## Recent preparation policy; underlying nominal domains and limits remain enforced.
    times*: AccumulationTimesConfig ## Times preparation policy; underlying nominal domains and limits remain enforced.
    validators*: AccumulationValidatorsConfig ## Validators preparation policy; underlying nominal domains and limits remain enforced.
    activity*: AccumulationActivityConfig ## Activity preparation policy; underlying nominal domains and limits remain enforced.
    preimages*: AccumulationPreimageLimits ## Preimages preparation policy; underlying nominal domains and limits remain enforced.
    authorization*: AccumulationAuthorizationLimits ## Authorization preparation policy; underlying nominal domains and limits remain enforced.
    consensus*: AccumulationConsensusLimits ## Consensus preparation policy; underlying nominal domains and limits remain enforced.
  AccumulationCompletionLimits* = object ## Convenience stopped execution/state policy with explicit ownership of each phase group.
    finalization*: AccumulationOutputHistoryLimits ## Execution-side output/history finalization budget.
    composition*: AccumulationCompositionLimits ## State-side composition budgets; no execution or finalization replay.
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

proc prepareAccumulationComposition*(source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): AccumulationCompletionResult =
  ## Compose existing state phases from one immutable execution successor, without finalizing or replaying guests.
  if source.finalAccumulationInfo.error != AccumulationFinalizationError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.InvalidSource) # Defaults authorize no state work or hashing.
  let history = prepareAccumulationHistory(source, limits.history)
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


proc prepareStoppedAccumulation*(source: StoppedAccumulation,
    limits: AccumulationCompletionLimits): AccumulationCompletionResult =
  ## Convenience orchestration finalizes execution once, then uses the sole state composition entry.
  if source.stoppedKind == StoppedAccumulationKind.Uninitialized:
    return AccumulationCompletionResult(status: AccumulationCompletionError.InvalidSource) # Keep the public default-source reason stable.
  let finalization = prepareFinalAccumulation(source, limits.finalization)
  if finalization.error != AccumulationFinalizationError.None:
    return AccumulationCompletionResult(status: AccumulationCompletionError.FinalizationFailure,
      finalizationReason: finalization) # No partially finalized source enters state composition.
  prepareAccumulationComposition(finalization.value, limits.composition)
