# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve authenticated initial-round global ownership around the reusable explicit-input phase.
## Pure phase success cannot construct this bound owner or replace its admitted source chain.
import ../codec/state_authorization as codec_state_authorization
import ../codec/state_safrole as codec_state_safrole
import ./accumulation_global_phase as state_accumulation_global_phase
import ./accumulation_provision_stage as state_accumulation_provision_stage
import ./accumulation_account_stage as state_accumulation_account_stage
import ./accumulation_block_guests as state_accumulation_block_guests
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./accumulation_global_roles as state_accumulation_global_roles
import ./store as state_store

type
  AccumulationGlobalStageError* = AccumulationGlobalPhaseError ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  AccumulationGlobalStageLimits* = AccumulationGlobalPhaseLimits ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  AccumulationGlobalStageInfo* = AccumulationGlobalPhaseInfo ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  GlobalStageData = ref object # Immutable acyclic wrapper retains genuine admission separately from its pure projection.
    source: PreparedAccumulationProvisionStage
    phase: PreparedAccumulationGlobalPhase
  PreparedAccumulationGlobalStage* = object ## Only the bound adapter constructs this authenticated phase owner.
    data: nil GlobalStageData
  AccumulationGlobalStageResult*[T] = object ## Private wrapper alternatives prevent pure/default payloads from fabricating authenticated success.
    case status: AccumulationGlobalStageError
    of None:
      completed: T
    of RoleFailure:
      roleReason: AccumulationGlobalRoleError
    of QueueFailure:
      queueReason: AuthorizationError
    of StagingFailure:
      stagingReason: StateComponentError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/preflight refusals carry no complete authenticated owner.

func error*[T](outcome: AccumulationGlobalStageResult[T]): AccumulationGlobalStageError =
  ## Read the selected reason without allowing retagging.
  outcome.status
func value*[T](outcome: AccumulationGlobalStageResult[T]): T {.inline, requires: outcome.status ==
    AccumulationGlobalStageError.None.} =
  ## Extract only a fully bound successful owner or observation.
  outcome.completed
func roleFailure*[T](outcome: AccumulationGlobalStageResult[
    T]): AccumulationGlobalRoleError {.inline, requires: outcome.status ==
    AccumulationGlobalStageError.RoleFailure.} =
  ## Inspect only the genuine selected roleReason refusal.
  outcome.roleReason
func queueFailure*[T](outcome: AccumulationGlobalStageResult[T]): AuthorizationError {.inline,
    requires: outcome.status == AccumulationGlobalStageError.QueueFailure.} =
  ## Inspect only the genuine selected queueReason refusal.
  outcome.queueReason
func stagingFailure*[T](outcome: AccumulationGlobalStageResult[T]): StateComponentError {.inline,
    requires: outcome.status == AccumulationGlobalStageError.StagingFailure.} =
  ## Inspect only the genuine selected stagingReason refusal.
  outcome.stagingReason
func storeFailure*[T](outcome: AccumulationGlobalStageResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationGlobalStageError.StoreFailure.} =
  ## Inspect only the genuine selected storeReason refusal.
  outcome.storeReason

proc prepareAccumulationGlobalStage*(provisions: PreparedAccumulationProvisionStage,
    limits: AccumulationGlobalStageLimits): AccumulationGlobalStageResult[
    PreparedAccumulationGlobalStage] =
  ## Preserve genuine source authority before delegating selected-state semantics exactly once.
  let projection = provisions.provisionStagePhase
  if projection.error != AccumulationProvisionStageError.None:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.InvalidSource) # No pure/default successor grants block admission authority.
  let guests = provisions.provisionStageAccounts.value.accountStageGuests.value
  let profile = guests.guestRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.blockTransitionProfile
  if uint64(limits.roles.privileges.cores) != uint64(profile.cores):
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.InvalidConfig) # Retain authenticated shape validation even for empty producer sets.
  let projected = prepareAccumulationGlobalPhase(projection.value, limits)
  case projected.error
  of AccumulationGlobalPhaseError.None:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.None, completed: PreparedAccumulationGlobalStage(
        data: GlobalStageData(source: provisions, phase: projected.value)))
  of AccumulationGlobalPhaseError.RoleFailure:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.RoleFailure,
        roleReason: projected.roleFailure) # Preserve the actual failed phase reason.
  of AccumulationGlobalPhaseError.QueueFailure:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.QueueFailure,
        queueReason: projected.queueFailure) # Preserve the actual failed phase reason.
  of AccumulationGlobalPhaseError.StagingFailure:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.StagingFailure,
        stagingReason: projected.stagingFailure) # Preserve the actual failed phase reason.
  of AccumulationGlobalPhaseError.StoreFailure:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.StoreFailure,
        storeReason: projected.storeFailure) # Preserve the actual failed phase reason.
  of AccumulationGlobalPhaseError.Uninitialized:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.Uninitialized) # Reason-only failure never grants a partial phase.
  of AccumulationGlobalPhaseError.InvalidSource:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.InvalidSource) # Reason-only failure never grants a partial phase.
  of AccumulationGlobalPhaseError.InvalidConfig:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.InvalidConfig) # Reason-only failure never grants a partial phase.
  of AccumulationGlobalPhaseError.InvalidState:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.InvalidState) # Reason-only failure never grants a partial phase.
  of AccumulationGlobalPhaseError.LimitExceeded:
    AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.LimitExceeded) # Reason-only failure never grants a partial phase.

proc globalStageInfo*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    AccumulationGlobalStageInfo] =
  ## Retain the complete globalStageInfo projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[AccumulationGlobalStageInfo](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[AccumulationGlobalStageInfo](
      status: AccumulationGlobalStageError.None, completed: data.phase.globalPhaseInfo.value)

proc globalStageRoles*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    PreparedAccumulationGlobalRoles] =
  ## Retain the complete globalStageRoles projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalRoles](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[PreparedAccumulationGlobalRoles](
      status: AccumulationGlobalStageError.None, completed: data.phase.globalPhaseRoles.value)

proc globalStageSnapshot*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    StateStoreSnapshot] =
  ## Retain the complete globalStageSnapshot projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[StateStoreSnapshot](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[StateStoreSnapshot](status: AccumulationGlobalStageError.None,
      completed: data.phase.globalPhaseSnapshot.value)

proc globalStagePhase*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    PreparedAccumulationGlobalPhase] =
  ## Retain the complete globalStagePhase projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalPhase](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[PreparedAccumulationGlobalPhase](
      status: AccumulationGlobalStageError.None, completed: data.phase)

proc globalStageProvisions*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    PreparedAccumulationProvisionStage] =
  ## Retain the complete globalStageProvisions projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[PreparedAccumulationProvisionStage](
      status: AccumulationGlobalStageError.None, completed: data.source)
