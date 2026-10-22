# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fulfill original terminal provisions after complete selected accounts, including requests belonging to new accounts.
## Annulment never filters original provide contributions; all work and Merkle changes remain on a private complete fork.
import ./[accumulation_account_stage, accumulation_block_guests, accumulation_coverage,
  accumulation_annulment, accumulation_outcome, accumulation_effects, accumulation_provisions, store]

type
  AccumulationProvisionStageError* {.pure.} = enum ## Refusals expose no partial union, account map or proposed root.
    Uninitialized, None, InvalidSource, LimitExceeded, ProvisionFailure, StoreFailure
  ProvisionStageData = ref object # Retained immutable owners form an acyclic account/guest/provider graph.
    accounts: PreparedAccumulationAccountStage
    plan: PreparedAccumulationProvisions
    snapshot: StateStoreSnapshot
  PreparedAccumulationProvisionStage* = object ## Only full original union and private fulfillment constructs this successor phase.
    data: nil ProvisionStageData
  AccumulationProvisionStageResult*[T] = object ## Private reason-only failures never grant success extraction.
    case status: AccumulationProvisionStageError
    of None:
      completed: T
    of ProvisionFailure:
      provisionReason: AccumulationProvisionError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/source/extent refusals retain no incomplete provider array.

func error*[T](outcome: AccumulationProvisionStageResult[T]): AccumulationProvisionStageError =
  ## Inspect the selected alternative without granting retagging.
  outcome.status
func value*[T](outcome: AccumulationProvisionStageResult[T]): T {.inline,
    requires: outcome.status == AccumulationProvisionStageError.None.} =
  ## Extract complete phase ownership only after selected success.
  outcome.completed
func provisionFailure*[T](outcome: AccumulationProvisionStageResult[
    T]): AccumulationProvisionError {.inline,

requires: outcome.status == AccumulationProvisionStageError.ProvisionFailure.} =
  ## Inspect only the actual union/fulfillment refusal.
  outcome.provisionReason
func storeFailure*[T](outcome: AccumulationProvisionStageResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationProvisionStageError.StoreFailure.} =
  ## Inspect only the actual private-fork refusal.
  outcome.storeReason
proc prepareAccumulationProvisionStage*(accounts: PreparedAccumulationAccountStage,
    limits: AccumulationProvisionUnionLimits): AccumulationProvisionStageResult[
        PreparedAccumulationProvisionStage] =
  ## Union every genuine original selected terminal context, including canceled producers, then fulfill against selected M/n state.
  template fail(reason: AccumulationProvisionStageError) =
    return AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](status: reason)
  let guests = accounts.accountStageGuests
  if guests.error != AccumulationAccountStageError.None:
    fail(AccumulationProvisionStageError.InvalidSource) # A default or caller-authored account projection grants no source authority.
  let coverage = guests.value.guestCoverage.value
  let original = coverage.coverageAnnulment.value
  let count = original.annulmentInfo.value.outcomes
  if uint64(count) > uint64(limits.contexts) or count > high(int) div sizeof(AccumulationEffectContext):
    fail(AccumulationProvisionStageError.LimitExceeded) # Bound provider traversal and handle capture before allocation.
  var contexts = newSeq[AccumulationEffectContext](count)
  for ordinal in 0..<count:
    contexts[ordinal] = original.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
        ordinal))).value.outcomeContext.value # N clears selected effects but retains these original provisions.
  let prepared = prepareAccumulationProvisions(contexts, limits)
  if prepared.error != AccumulationProvisionError.None:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
      status: AccumulationProvisionStageError.ProvisionFailure, provisionReason: prepared.error)
  let forked = forkStateStore(accounts.accountStageSnapshot.value)
  if forked.error != StateStoreError.None:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
      status: AccumulationProvisionStageError.StoreFailure, storeReason: forked.error)
  var working = forked.value
  let fulfilled = integrateAccumulationProvisions(working, prepared.value,
      coverage.coverageInfo.value.slot)
  if fulfilled.error != AccumulationProvisionError.None:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
      status: AccumulationProvisionStageError.ProvisionFailure, provisionReason: fulfilled.error)
  AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
    status: AccumulationProvisionStageError.None,
    completed: PreparedAccumulationProvisionStage(data: ProvisionStageData(accounts: accounts,
      plan: prepared.value, snapshot: fulfilled.value)))

proc provisionStageAccounts*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    PreparedAccumulationAccountStage] =
  ## Retain the exact accounts of this completely fulfilled private phase; defaults expose no successor.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[PreparedAccumulationAccountStage](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[PreparedAccumulationAccountStage](
      status: AccumulationProvisionStageError.None, completed: data.accounts)

proc provisionStagePlan*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    PreparedAccumulationProvisions] =
  ## Retain the exact plan of this completely fulfilled private phase; defaults expose no successor.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisions](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[PreparedAccumulationProvisions](
      status: AccumulationProvisionStageError.None, completed: data.plan)

proc provisionStageSnapshot*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    StateStoreSnapshot] =
  ## Retain the exact snapshot of this completely fulfilled private phase; defaults expose no successor.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[StateStoreSnapshot](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[StateStoreSnapshot](status: AccumulationProvisionStageError.None,
      completed: data.snapshot)
