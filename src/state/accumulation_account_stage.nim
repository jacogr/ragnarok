# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve authenticated initial-round account ownership around the reusable explicit-input phase.
## Pure phase success cannot construct this bound owner or replace its admitted source chain.
import ./[accumulation_account_phase, accumulation_block_guests, accumulation_coverage,
  accumulation_account_selection, accumulation_creation_union, accumulation_selected_writes, store]

type
  AccumulationAccountStageError* = AccumulationAccountPhaseError ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  AccumulationAccountStageLimits* = AccumulationAccountPhaseLimits ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  AccumulationAccountStageInfo* = AccumulationAccountPhaseInfo ## Preserve the existing public policy/reason shape while sharing the phase implementation.
  AccountStageData = ref object # Immutable acyclic wrapper retains genuine admission separately from its pure projection.
    source: BlockAccumulationGuests
    phase: PreparedAccumulationAccountPhase
  PreparedAccumulationAccountStage* = object ## Only the bound adapter constructs this authenticated phase owner.
    data: nil AccountStageData
  AccumulationAccountStageResult*[T] = object ## Private wrapper alternatives prevent pure/default payloads from fabricating authenticated success.
    case status: AccumulationAccountStageError
    of None:
      completed: T
    of SelectionFailure:
      selectionReason: AccumulationAccountSelectionError
    of CreationFailure:
      creationReason: AccumulationCreationError
    of WriteFailure:
      writeReason: SelectedAccountWriteError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/preflight refusals carry no complete authenticated owner.

func error*[T](outcome: AccumulationAccountStageResult[T]): AccumulationAccountStageError =
  ## Read the selected reason without allowing retagging.
  outcome.status
func value*[T](outcome: AccumulationAccountStageResult[T]): T {.inline, requires: outcome.status ==
    AccumulationAccountStageError.None.} =
  ## Extract only a fully bound successful owner or observation.
  outcome.completed
func selectionFailure*[T](outcome: AccumulationAccountStageResult[
    T]): AccumulationAccountSelectionError {.inline, requires: outcome.status ==
    AccumulationAccountStageError.SelectionFailure.} =
  ## Inspect only the genuine selected selectionReason refusal.
  outcome.selectionReason
func creationFailure*[T](outcome: AccumulationAccountStageResult[
    T]): AccumulationCreationError {.inline, requires: outcome.status ==
    AccumulationAccountStageError.CreationFailure.} =
  ## Inspect only the genuine selected creationReason refusal.
  outcome.creationReason
func writeFailure*[T](outcome: AccumulationAccountStageResult[
    T]): SelectedAccountWriteError {.inline, requires: outcome.status ==
    AccumulationAccountStageError.WriteFailure.} =
  ## Inspect only the genuine selected writeReason refusal.
  outcome.writeReason
func storeFailure*[T](outcome: AccumulationAccountStageResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationAccountStageError.StoreFailure.} =
  ## Inspect only the genuine selected storeReason refusal.
  outcome.storeReason

proc prepareAccumulationAccountStage*(guests: BlockAccumulationGuests,
    limits: AccumulationAccountStageLimits): AccumulationAccountStageResult[
    PreparedAccumulationAccountStage] =
  ## Preserve genuine source authority before delegating selected-state semantics exactly once.
  let coverage = guests.guestCoverage
  if coverage.error != BlockGuestError.None:
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.InvalidSource) # Preserve genuine initial-round authority before invoking the reusable phase.
  let projected = prepareAccumulationAccountPhase(coverage.value, limits)
  case projected.error
  of AccumulationAccountPhaseError.None:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.None, completed: PreparedAccumulationAccountStage(
        data: AccountStageData(source: guests, phase: projected.value)))
  of AccumulationAccountPhaseError.SelectionFailure:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.SelectionFailure,
        selectionReason: projected.selectionFailure) # Preserve the actual failed phase reason.
  of AccumulationAccountPhaseError.CreationFailure:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.CreationFailure,
        creationReason: projected.creationFailure) # Preserve the actual failed phase reason.
  of AccumulationAccountPhaseError.WriteFailure:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.WriteFailure,
        writeReason: projected.writeFailure) # Preserve the actual failed phase reason.
  of AccumulationAccountPhaseError.StoreFailure:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.StoreFailure,
        storeReason: projected.storeFailure) # Preserve the actual failed phase reason.
  of AccumulationAccountPhaseError.Uninitialized:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.Uninitialized) # Reason-only failure never grants a partial phase.
  of AccumulationAccountPhaseError.InvalidSource:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.InvalidSource) # Reason-only failure never grants a partial phase.
  of AccumulationAccountPhaseError.LimitExceeded:
    AccumulationAccountStageResult[PreparedAccumulationAccountStage](
        status: AccumulationAccountStageError.LimitExceeded) # Reason-only failure never grants a partial phase.

proc accountStageInfo*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    AccumulationAccountStageInfo] =
  ## Retain the complete accountStageInfo projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[AccumulationAccountStageInfo](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[AccumulationAccountStageInfo](
      status: AccumulationAccountStageError.None, completed: data.phase.accountPhaseInfo.value)

proc accountStageSelection*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedAccumulationAccountSelection] =
  ## Retain the complete accountStageSelection projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedAccumulationAccountSelection](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedAccumulationAccountSelection](
      status: AccumulationAccountStageError.None, completed: data.phase.accountPhaseSelection.value)

proc accountStageCreation*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedAccumulationCreationUnion] =
  ## Retain the complete accountStageCreation projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedAccumulationCreationUnion](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedAccumulationCreationUnion](
      status: AccumulationAccountStageError.None, completed: data.phase.accountPhaseCreation.value)

proc accountStageWrites*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedSelectedAccountWrites] =
  ## Retain the complete accountStageWrites projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedSelectedAccountWrites](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedSelectedAccountWrites](
      status: AccumulationAccountStageError.None, completed: data.phase.accountPhaseWrites.value)

proc accountStageSnapshot*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    StateStoreSnapshot] =
  ## Retain the complete accountStageSnapshot projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[StateStoreSnapshot](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[StateStoreSnapshot](status: AccumulationAccountStageError.None,
      completed: data.phase.accountPhaseSnapshot.value)

proc accountStagePhase*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedAccumulationAccountPhase] =
  ## Retain the complete accountStagePhase projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedAccumulationAccountPhase](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedAccumulationAccountPhase](
      status: AccumulationAccountStageError.None, completed: data.phase)

proc accountStageGuests*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    BlockAccumulationGuests] =
  ## Retain the complete accountStageGuests projection only from genuine initialized bound ownership.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[BlockAccumulationGuests](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[BlockAccumulationGuests](
      status: AccumulationAccountStageError.None, completed: data.source)
