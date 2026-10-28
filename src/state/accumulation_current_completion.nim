# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compose all current PVM state phases from a terminal sequence; failures retain no successful prefix.
import ./accumulation_current_statistics as state_accumulation_current_statistics
import ./accumulation_current_accounts as state_accumulation_current_accounts
import ./accumulation_current_finalization as state_accumulation_current_finalization
import ./accumulation_current_ready as state_accumulation_current_ready
import ./accumulation_current_recent as state_accumulation_current_recent
import ./accumulation_current_validators as state_accumulation_current_validators
import ./accumulation_current_activity as state_accumulation_current_activity
import ./accumulation_current_preimages as state_accumulation_current_preimages
import ./accumulation_current_authorization as state_accumulation_current_authorization
import ./accumulation_current_consensus as state_accumulation_current_consensus
import ./accumulation_current_driver as state_accumulation_current_driver
import ./accumulation_round as state_accumulation_round
import ./accumulation_accounts as state_accumulation_accounts
import ./accumulation_ready as state_accumulation_ready
import ./accumulation_recent as state_accumulation_recent
import ./accumulation_validators as state_accumulation_validators
import ./accumulation_activity as state_accumulation_activity
import ./accumulation_preimages as state_accumulation_preimages
import ./accumulation_authorization as state_accumulation_authorization
import ./accumulation_consensus as state_accumulation_consensus
import ../chain/parameters as chain_parameters

type
  CurrentAccumulationCompositionLimits* = object ## Each state phase keeps its existing independent local resource ceilings.
    statistics*: CurrentAccumulationStatisticsLimits ## Explicit statistics policy; protocol facts remain source-derived.
    accounts*: AccumulationAccountConfig ## Explicit accounts policy; protocol facts remain source-derived.
    finalization*: CurrentAccumulationFinalizationConfig ## Explicit finalization policy; protocol facts remain source-derived.
    ready*: AccumulationReadyConfig ## Explicit ready policy; protocol facts remain source-derived.
    recent*: AccumulationRecentConfig ## Explicit recent policy; protocol facts remain source-derived.
    validators*: AccumulationValidatorsConfig ## Explicit validators policy; protocol facts remain source-derived.
    activity*: AccumulationActivityConfig ## Explicit activity policy; protocol facts remain source-derived.
    preimages*: AccumulationPreimageLimits ## Explicit preimages policy; protocol facts remain source-derived.
    authorization*: AccumulationAuthorizationLimits ## Explicit authorization policy; protocol facts remain source-derived.
    consensus*: AccumulationConsensusLimits ## Explicit consensus policy; protocol facts remain source-derived.
  CurrentAccumulationCompletionLimits* = object ## Execution runs once before state-only composition under separate policy groups.
    execution*: CurrentSequenceDriverLimits            ## Initial and continuation execution/planning ceilings.
    composition*: CurrentAccumulationCompositionLimits ## Terminal state composition ceilings.
  CurrentAccumulationCompletionError* {.pure.} = enum ## No default or refused stage exposes a usable prefix.
    Uninitialized, None, InvalidSource, SequenceFailure, StatisticsFailure, AccountsFailure,
      FinalizationFailure, ReadyFailure, RecentFailure, ValidatorsFailure, ActivityFailure,
      PreimagesFailure, AuthorizationFailure, ConsensusFailure
  CurrentAccumulationCompletionResult* = object ## Actual failed child alternatives remain guarded and separate from complete success.
    case status: CurrentAccumulationCompletionError
    of None: completed: PreparedCurrentAccumulationConsensus
    of SequenceFailure: sequenceReason: CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence]
    of StatisticsFailure: statisticsReason: CurrentAccumulationStatisticsResult[PreparedCurrentAccumulationStatistics]
    of AccountsFailure: accountsReason: CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts]
    of FinalizationFailure: finalizationReason: CurrentAccumulationFinalizationResult[PreparedCurrentAccumulationFinalization]
    of ReadyFailure: readyReason: CurrentAccumulationReadyResult[PreparedCurrentAccumulationReady]
    of RecentFailure: recentReason: CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent]
    of ValidatorsFailure: validatorsReason: CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators]
    of ActivityFailure: activityReason: CurrentAccumulationActivityResult[PreparedCurrentAccumulationActivity]
    of PreimagesFailure: preimagesReason: CurrentAccumulationPreimageResult[PreparedCurrentAccumulationPreimages]
    of AuthorizationFailure: authorizationReason: CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization]
    of ConsensusFailure: consensusReason: CurrentAccumulationConsensusResult[PreparedCurrentAccumulationConsensus]
    else: discard # Default/invalid input carries no state or source authority.
func error*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationCompletionError =
  ## Inspect the selected outer stage without writable discriminator access.
  outcome.status
func value*(outcome: CurrentAccumulationCompletionResult): PreparedCurrentAccumulationConsensus {.inline,
    requires: outcome.status == CurrentAccumulationCompletionError.None.} =
  ## Extract only the complete current state composition owner.
  outcome.completed
func sequenceFailure*(outcome: CurrentAccumulationCompletionResult): CurrentSequenceDriverResult[
    CompletedCurrentAccumulationSequence] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.SequenceFailure.} =
  ## Inspect only an actual refused current execution sequence.
  outcome.sequenceReason
func statisticsFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationStatisticsResult[
    PreparedCurrentAccumulationStatistics] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.StatisticsFailure.} =
  ## Inspect only the actual failed statistics parent, never a successful earlier owner.
  outcome.statisticsReason
func accountsFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationAccountResult[
    PreparedCurrentAccumulationAccounts] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.AccountsFailure.} =
  ## Inspect only the actual failed accounts parent, never a successful earlier owner.
  outcome.accountsReason
func finalizationFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationFinalizationResult[
    PreparedCurrentAccumulationFinalization] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.FinalizationFailure.} =
  ## Inspect only the actual failed finalization parent, never a successful earlier owner.
  outcome.finalizationReason
func readyFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationReadyResult[
    PreparedCurrentAccumulationReady] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.ReadyFailure.} =
  ## Inspect only the actual failed ready parent, never a successful earlier owner.
  outcome.readyReason
func recentFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationRecentResult[
    PreparedCurrentAccumulationRecent] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.RecentFailure.} =
  ## Inspect only the actual failed recent parent, never a successful earlier owner.
  outcome.recentReason
func validatorsFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationValidatorsResult[
    PreparedCurrentAccumulationValidators] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.ValidatorsFailure.} =
  ## Inspect only the actual failed validators parent, never a successful earlier owner.
  outcome.validatorsReason
func activityFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationActivityResult[
    PreparedCurrentAccumulationActivity] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.ActivityFailure.} =
  ## Inspect only the actual failed activity parent, never a successful earlier owner.
  outcome.activityReason
func preimagesFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationPreimageResult[
    PreparedCurrentAccumulationPreimages] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.PreimagesFailure.} =
  ## Inspect only the actual failed preimages parent, never a successful earlier owner.
  outcome.preimagesReason
func authorizationFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationAuthorizationResult[
    PreparedCurrentAccumulationAuthorization] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.AuthorizationFailure.} =
  ## Inspect only the actual failed authorization parent, never a successful earlier owner.
  outcome.authorizationReason
func consensusFailure*(outcome: CurrentAccumulationCompletionResult): CurrentAccumulationConsensusResult[
    PreparedCurrentAccumulationConsensus] {.inline, requires: outcome.status ==
    CurrentAccumulationCompletionError.ConsensusFailure.} =
  ## Inspect only the actual failed consensus parent, never a successful earlier owner.
  outcome.consensusReason
proc prepareCurrentAccumulationComposition*(source: CompletedCurrentAccumulationSequence,
    limits: CurrentAccumulationCompositionLimits): CurrentAccumulationCompletionResult =
  ## State-only orchestration consumes one genuine terminal source without guest execution or canonical mutation.
  if source.completedSequenceInfo.error != CurrentSequenceDriverError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.InvalidSource)
  let statistics = prepareCurrentAccumulationStatistics(source, limits.statistics)
  if statistics.error != CurrentAccumulationStatisticsError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.StatisticsFailure,
      statisticsReason: statistics) # All successful local prefixes retire on refusal.
  let accounts = prepareCurrentAccumulationAccounts(statistics.value, limits.accounts)
  if accounts.error != CurrentAccumulationAccountError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.AccountsFailure,
      accountsReason: accounts) # All successful local prefixes retire on refusal.
  let finalization = prepareCurrentAccumulationFinalization(accounts.value, limits.finalization)
  if finalization.error != CurrentAccumulationFinalizationError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.FinalizationFailure,
      finalizationReason: finalization) # All successful local prefixes retire on refusal.
  let ready = prepareCurrentAccumulationReady(finalization.value, limits.ready)
  if ready.error != CurrentAccumulationReadyError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.ReadyFailure,
      readyReason: ready) # All successful local prefixes retire on refusal.
  let recent = prepareCurrentAccumulationRecent(ready.value, limits.recent)
  if recent.error != CurrentAccumulationRecentError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.RecentFailure,
      recentReason: recent) # All successful local prefixes retire on refusal.
  let validators = prepareCurrentAccumulationValidators(recent.value, limits.validators)
  if validators.error != CurrentAccumulationValidatorsError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.ValidatorsFailure,
      validatorsReason: validators) # All successful local prefixes retire on refusal.
  let activity = prepareCurrentAccumulationActivity(validators.value, limits.activity)
  if activity.error != CurrentAccumulationActivityError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.ActivityFailure,
      activityReason: activity) # All successful local prefixes retire on refusal.
  let preimages = prepareCurrentAccumulationPreimages(activity.value, limits.preimages)
  if preimages.error != CurrentAccumulationPreimageError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.PreimagesFailure,
      preimagesReason: preimages) # All successful local prefixes retire on refusal.
  let authorization = prepareCurrentAccumulationAuthorization(preimages.value, limits.authorization)
  if authorization.error != CurrentAccumulationAuthorizationError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.AuthorizationFailure,
      authorizationReason: authorization) # All successful local prefixes retire on refusal.
  let consensus = prepareCurrentAccumulationConsensus(authorization.value, limits.consensus)
  if consensus.error != CurrentAccumulationConsensusError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.ConsensusFailure,
      consensusReason: consensus) # All successful local prefixes retire on refusal.
  CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.None,
      completed: consensus.value)
proc runCurrentAccumulationCompletion*(round: BlockAccumulationRound, parameters: Parameters,
    limits: CurrentAccumulationCompletionLimits): CurrentAccumulationCompletionResult =
  ## Drive the initial and subsequent current guests once, then run the same terminal composition entry point.
  let executed = runCurrentBlockAccumulationSequence(round, parameters, limits.execution)
  if executed.error != CurrentSequenceDriverError.None:
    return CurrentAccumulationCompletionResult(status: CurrentAccumulationCompletionError.SequenceFailure,
      sequenceReason: executed) # Preserve the actual failed execution stage; no state composition runs.
  prepareCurrentAccumulationComposition(executed.value, limits.composition)
