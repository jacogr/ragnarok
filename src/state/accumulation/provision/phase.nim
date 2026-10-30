# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fulfill original terminal provisions after complete selected accounts, including requests belonging to new accounts.
## Annulment never filters original provide contributions; all work and Merkle changes remain on a private complete fork.
## This reusable phase trusts explicit coverage/frame configuration; it cannot construct an authenticated Stage owner.
import ../account/phase as accumulation_account_phase
import ../[coverage as accumulation_coverage, annulment as accumulation_annulment,
    outcome as accumulation_outcome, effects as accumulation_effects,
    provisions as accumulation_provisions]
import ../../store

type
  AccumulationProvisionPhaseError* {.pure.} = enum ## Refusals expose no partial union, account map or proposed root.
    Uninitialized, None, InvalidSource, LimitExceeded, ProvisionFailure, StoreFailure
  ProvisionPhaseData = ref object # Retained immutable owners form an acyclic account/guest/provider graph.
    accounts: PreparedAccumulationAccountPhase
    plan: PreparedAccumulationProvisions
    snapshot: StateStoreSnapshot
  PreparedAccumulationProvisionPhase* = object ## Only full original union and private fulfillment constructs this successor phase.
    data: nil ProvisionPhaseData
  AccumulationProvisionPhaseResult*[T] = object ## Private reason-only failures never grant success extraction.
    case status: AccumulationProvisionPhaseError
    of None:
      completed: T
    of ProvisionFailure:
      provisionReason: AccumulationProvisionError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/source/extent refusals retain no incomplete provider array.

func error*[T](outcome: AccumulationProvisionPhaseResult[T]): AccumulationProvisionPhaseError =
  ## Inspect the selected alternative without granting retagging.
  outcome.status

func value*[T](outcome: AccumulationProvisionPhaseResult[T]): T {.inline,
    requires: outcome.status == AccumulationProvisionPhaseError.None.} =
  ## Extract complete phase ownership only after selected success.
  outcome.completed

func provisionFailure*[T](outcome: AccumulationProvisionPhaseResult[
    T]): AccumulationProvisionError {.inline,

requires: outcome.status == AccumulationProvisionPhaseError.ProvisionFailure.} =
  ## Inspect only the actual union/fulfillment refusal.
  outcome.provisionReason

func storeFailure*[T](outcome: AccumulationProvisionPhaseResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationProvisionPhaseError.StoreFailure.} =
  ## Inspect only the actual private-fork refusal.
  outcome.storeReason

proc prepareAccumulationProvisionPhase*(accounts: PreparedAccumulationAccountPhase,
    limits: AccumulationProvisionUnionLimits): AccumulationProvisionPhaseResult[
        PreparedAccumulationProvisionPhase] =
  ## Union every genuine original selected terminal context, including canceled producers, then fulfill against selected M/n state.
  template fail(reason: AccumulationProvisionPhaseError) =
    return AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase](status: reason)
  let projection = accounts.accountPhaseCoverage
  if projection.error != AccumulationAccountPhaseError.None:
    fail(AccumulationProvisionPhaseError.InvalidSource) # A default account phase grants no complete coverage source.
  let coverage = projection.value
  let original = coverage.coverageAnnulment.value
  let count = original.annulmentInfo.value.outcomes
  if uint64(count) > uint64(limits.contexts) or count > high(int) div sizeof(AccumulationEffectContext):
    fail(AccumulationProvisionPhaseError.LimitExceeded) # Bound provider traversal and handle capture before allocation.
  var contexts = newSeq[AccumulationEffectContext](count)
  for ordinal in 0..<count:
    contexts[ordinal] = original.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
        ordinal))).value.outcomeContext.value # N clears selected effects but retains these original provisions.
  let prepared = prepareAccumulationProvisions(contexts, limits)
  if prepared.error != AccumulationProvisionError.None:
    return AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase](
      status: AccumulationProvisionPhaseError.ProvisionFailure, provisionReason: prepared.error)
  let forked = forkStateStore(accounts.accountPhaseSnapshot.value)
  if forked.error != StateStoreError.None:
    return AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase](
      status: AccumulationProvisionPhaseError.StoreFailure, storeReason: forked.error)
  var working = forked.value
  let fulfilled = integrateAccumulationProvisions(working, prepared.value,
      coverage.coverageInfo.value.slot)
  if fulfilled.error != AccumulationProvisionError.None:
    return AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase](
      status: AccumulationProvisionPhaseError.ProvisionFailure, provisionReason: fulfilled.error)
  AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase](
    status: AccumulationProvisionPhaseError.None,
    completed: PreparedAccumulationProvisionPhase(data: ProvisionPhaseData(accounts: accounts,
      plan: prepared.value, snapshot: fulfilled.value)))

proc provisionPhaseAccounts*(stage: PreparedAccumulationProvisionPhase): AccumulationProvisionPhaseResult[
    PreparedAccumulationAccountPhase] =
  ## Retain the exact accounts of this completely fulfilled private phase; defaults expose no successor.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionPhaseResult[PreparedAccumulationAccountPhase](
        status: AccumulationProvisionPhaseError.Uninitialized)
  AccumulationProvisionPhaseResult[PreparedAccumulationAccountPhase](
      status: AccumulationProvisionPhaseError.None, completed: data.accounts)

proc provisionPhasePlan*(stage: PreparedAccumulationProvisionPhase): AccumulationProvisionPhaseResult[
    PreparedAccumulationProvisions] =
  ## Retain the exact plan of this completely fulfilled private phase; defaults expose no successor.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionPhaseResult[PreparedAccumulationProvisions](
        status: AccumulationProvisionPhaseError.Uninitialized)
  AccumulationProvisionPhaseResult[PreparedAccumulationProvisions](
      status: AccumulationProvisionPhaseError.None, completed: data.plan)

proc provisionPhaseSnapshot*(stage: PreparedAccumulationProvisionPhase): AccumulationProvisionPhaseResult[
    StateStoreSnapshot] =
  ## Retain the exact snapshot of this completely fulfilled private phase; defaults expose no successor.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionPhaseResult[StateStoreSnapshot](
        status: AccumulationProvisionPhaseError.Uninitialized)
  AccumulationProvisionPhaseResult[StateStoreSnapshot](status: AccumulationProvisionPhaseError.None,
      completed: data.snapshot)
