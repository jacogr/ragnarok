# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind retained supplied logical declarations to the original qualified current successor and full parameter provenance.
## This read-only parent description does not export a producer manifest or certify propagation through later execution.
import ../codec/state_composition
import ./[current_state, inventory, supplied_logical_inventory]
type
  CurrentLogicalState* = object ## Private higher provenance owner and revalidated logical owner cannot be paired unchecked.
    initialized: bool
    source: CurrentStateSerialization
    logical: SuppliedLogicalInventory
  CurrentLogicalError* {.pure.} = enum ## Default and failed stages carry no complete logical parent prefix.
    Uninitialized, None, InvalidState, LogicalFailure
  CurrentLogicalResult*[T] = object ## Private alternatives preserve genuine logical admission/matching reasons.
    case status: CurrentLogicalError
    of None:
      completed: T
    of LogicalFailure:
      logicalReason: SuppliedLogicalResult[SuppliedLogicalInventory]
    else:
      discard # No default or failed result grants source/profile/key authority.
func error*[T](outcome: CurrentLogicalResult[T]): CurrentLogicalError =
  ## Observe selected immutable alternatives only.
  outcome.status
func value*[T](outcome: CurrentLogicalResult[T]): T {.inline, requires: outcome.status ==
    CurrentLogicalError.None.} =
  ## Extract only complete initialized source-bound logical evidence.
  outcome.completed
func logicalFailure*[T](outcome: CurrentLogicalResult[T]): SuppliedLogicalResult[
    SuppliedLogicalInventory] {.inline, requires: outcome.status ==
    CurrentLogicalError.LogicalFailure.} =
  ## Preserve the original failed supplied key/inventory/matching stage without a successful prefix.
  outcome.logicalReason
proc captureCurrentLogicalState*(source: CurrentStateSerialization, services: openArray[
    StateService], limits: SuppliedLogicalLimits): CurrentLogicalResult[CurrentLogicalState] =
  ## Revalidate stable supplied declarations against the original current inventory's exact physical source, never an equal-root replacement.
  let inventory = source.currentStateInventory
  if inventory.error != CurrentStateError.None:
    return CurrentLogicalResult[CurrentLogicalState](status: CurrentLogicalError.InvalidState)
  let logical = captureSuppliedLogicalInventory(inventory.value.inventorySource.value, services, limits)
  if logical.error != SuppliedLogicalError.None:
    return CurrentLogicalResult[CurrentLogicalState](status: CurrentLogicalError.LogicalFailure,
        logicalReason: logical) # Full matching binds the new compact capture to the original physical snapshot.
  CurrentLogicalResult[CurrentLogicalState](status: CurrentLogicalError.None,
    completed: CurrentLogicalState(initialized: true, source: source, logical: logical.value))
proc currentLogicalSource*(source: CurrentLogicalState): CurrentLogicalResult[
    CurrentStateSerialization] =
  ## Retain original producer/profile/full-Parameters provenance and its original compact capture.
  if not source.initialized:
    return CurrentLogicalResult[CurrentStateSerialization](
        status: CurrentLogicalError.Uninitialized)
  CurrentLogicalResult[CurrentStateSerialization](status: CurrentLogicalError.None,
      completed: source.source)
proc currentLogicalInventory*(source: CurrentLogicalState): CurrentLogicalResult[
    SuppliedLogicalInventory] =
  ## Retain the independently revalidated raw-key companion on the same exact physical snapshot.
  if not source.initialized:
    return CurrentLogicalResult[SuppliedLogicalInventory](status: CurrentLogicalError.Uninitialized)
  CurrentLogicalResult[SuppliedLogicalInventory](status: CurrentLogicalError.None,
      completed: source.logical)
