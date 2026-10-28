# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve authenticated initial-round provision ownership around the reusable explicit-input phase.
## Pure phase success cannot construct this bound owner or replace its admitted source chain.
import ./accumulation_provision_phase as state_accumulation_provision_phase
import ./accumulation_account_stage as state_accumulation_account_stage
import ./accumulation_provisions as state_accumulation_provisions
import ./store as state_store

type
  AccumulationProvisionStageError* = AccumulationProvisionPhaseError ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  ProvisionStageData = ref object # Immutable acyclic wrapper retains genuine admission separately from its pure projection.
    source: PreparedAccumulationAccountStage
    phase: PreparedAccumulationProvisionPhase
  PreparedAccumulationProvisionStage* = object ## Only the bound adapter constructs this authenticated phase owner.
    data: nil ProvisionStageData
  AccumulationProvisionStageResult*[T] = object ## Private wrapper alternatives prevent pure/default payloads from fabricating authenticated success.
    case status: AccumulationProvisionStageError
    of None:
      completed: T
    of ProvisionFailure:
      provisionReason: AccumulationProvisionError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/preflight refusals carry no complete authenticated owner.

func error*[T](outcome: AccumulationProvisionStageResult[T]): AccumulationProvisionStageError =
  ## Read the selected reason without allowing retagging.
  outcome.status
func value*[T](outcome: AccumulationProvisionStageResult[T]): T {.inline,
    requires: outcome.status == AccumulationProvisionStageError.None.} =
  ## Extract only a fully bound successful owner or observation.
  outcome.completed
func provisionFailure*[T](outcome: AccumulationProvisionStageResult[
    T]): AccumulationProvisionError {.inline, requires: outcome.status ==
    AccumulationProvisionStageError.ProvisionFailure.} =
  ## Inspect only the genuine selected provisionReason refusal.
  outcome.provisionReason
func storeFailure*[T](outcome: AccumulationProvisionStageResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationProvisionStageError.StoreFailure.} =
  ## Inspect only the genuine selected storeReason refusal.
  outcome.storeReason

proc prepareAccumulationProvisionStage*(accounts: PreparedAccumulationAccountStage,
    limits: AccumulationProvisionUnionLimits): AccumulationProvisionStageResult[
    PreparedAccumulationProvisionStage] =
  ## Preserve genuine source authority before delegating selected-state semantics exactly once.
  let projection = accounts.accountStagePhase
  if projection.error != AccumulationAccountStageError.None:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.InvalidSource) # A pure/default account owner cannot bypass the authenticated wrapper.
  let projected = prepareAccumulationProvisionPhase(projection.value, limits)
  case projected.error
  of AccumulationProvisionPhaseError.None:
    AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.None, completed: PreparedAccumulationProvisionStage(
        data: ProvisionStageData(source: accounts, phase: projected.value)))
  of AccumulationProvisionPhaseError.ProvisionFailure:
    AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.ProvisionFailure,
        provisionReason: projected.provisionFailure) # Preserve the actual failed phase reason.
  of AccumulationProvisionPhaseError.StoreFailure:
    AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.StoreFailure,
        storeReason: projected.storeFailure) # Preserve the actual failed phase reason.
  of AccumulationProvisionPhaseError.Uninitialized:
    AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.Uninitialized) # Reason-only failure never grants a partial phase.
  of AccumulationProvisionPhaseError.InvalidSource:
    AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.InvalidSource) # Reason-only failure never grants a partial phase.
  of AccumulationProvisionPhaseError.LimitExceeded:
    AccumulationProvisionStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationProvisionStageError.LimitExceeded) # Reason-only failure never grants a partial phase.

proc provisionStagePlan*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    PreparedAccumulationProvisions] =
  ## Retain the complete provisionStagePlan projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisions](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[PreparedAccumulationProvisions](
      status: AccumulationProvisionStageError.None, completed: data.phase.provisionPhasePlan.value)

proc provisionStageSnapshot*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    StateStoreSnapshot] =
  ## Retain the complete provisionStageSnapshot projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[StateStoreSnapshot](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[StateStoreSnapshot](status: AccumulationProvisionStageError.None,
      completed: data.phase.provisionPhaseSnapshot.value)

proc provisionStagePhase*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    PreparedAccumulationProvisionPhase] =
  ## Retain the complete provisionStagePhase projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[PreparedAccumulationProvisionPhase](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[PreparedAccumulationProvisionPhase](
      status: AccumulationProvisionStageError.None, completed: data.phase)

proc provisionStageAccounts*(stage: PreparedAccumulationProvisionStage): AccumulationProvisionStageResult[
    PreparedAccumulationAccountStage] =
  ## Retain the complete provisionStageAccounts projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationProvisionStageResult[PreparedAccumulationAccountStage](
        status: AccumulationProvisionStageError.Uninitialized)
  AccumulationProvisionStageResult[PreparedAccumulationAccountStage](
      status: AccumulationProvisionStageError.None, completed: data.source)
