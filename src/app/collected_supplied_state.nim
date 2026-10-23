# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Requalify complete explicitly supplied successor namespaces on a frozen genuine collected target.
import ./[chain, collected_supplied_plan]
import ../state/[current_state, current_logical, accumulation_current_update]
import ../codec/state_composition
type
  CollectedSuppliedError* {.pure.} = enum ## Invalid frozen source, stale canonical prior and original complete matching failures remain distinct.
    Uninitialized, None, InvalidPlan, StaleUpdate, StateFailure, LogicalFailure
  CollectedSuppliedResult* = object ## No failed complete matching or raw-key revalidation exposes a successful logical prefix.
    case status: CollectedSuppliedError
    of None: completed: CurrentLogicalState
    of StateFailure: stateReason: CurrentStateResult[CurrentStateSerialization]
    of LogicalFailure: logicalReason: CurrentLogicalResult[CurrentLogicalState]
    else: discard # Defaults and refused original-source selection carry no payload.
func error*(outcome: CollectedSuppliedResult): CollectedSuppliedError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*(outcome: CollectedSuppliedResult): CurrentLogicalState {.inline,
    requires: outcome.status == CollectedSuppliedError.None.} =
  ## Retain only whole actual current qualification and detached supplied logical identities.
  outcome.completed
func stateFailure*(outcome: CollectedSuppliedResult): CurrentStateResult[
    CurrentStateSerialization] {.inline, requires: outcome.status ==
    CollectedSuppliedError.StateFailure.} =
  ## Preserve exact complete matching, compact inventory and backend causes.
  outcome.stateReason
func logicalFailure*(outcome: CollectedSuppliedResult): CurrentLogicalResult[
    CurrentLogicalState] {.inline, requires: outcome.status ==
    CollectedSuppliedError.LogicalFailure.} =
  ## Preserve independently bounded original raw-key capture and complete revalidation failures.
  outcome.logicalReason
proc executeCollectedSupplied*(chain: ApplicationChain, plan: CollectedSuppliedPlan,
    declarations: openArray[StateService]): CollectedSuppliedResult =
  ## Stable borrowed declarations must match the entire actual target; no original-parent identity relation is inferred.
  let source = plan.collectedSuppliedUpdate
  if source.error != CollectedSuppliedPlanError.None:
    return CollectedSuppliedResult(status: CollectedSuppliedError.InvalidPlan)
  if not chain.canInstallPrepared(source.value):
    return CollectedSuppliedResult(status: CollectedSuppliedError.StaleUpdate)
  let limits = plan.collectedSuppliedLimits.value.logical
  let state = qualifyCurrentState(plan.collectedSuppliedGlobals.value, declarations,
      limits.inventory)
  if state.error != CurrentStateError.None:
    return CollectedSuppliedResult(status: CollectedSuppliedError.StateFailure, stateReason: state)
  let logical = captureCurrentLogicalState(state.value, declarations, limits)
  if logical.error != CurrentLogicalError.None:
    return CollectedSuppliedResult(status: CollectedSuppliedError.LogicalFailure,
        logicalReason: logical)
  CollectedSuppliedResult(status: CollectedSuppliedError.None, completed: logical.value)
