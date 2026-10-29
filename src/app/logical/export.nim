# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stage complete qualified logical declarations for bounded detached export without recapturing producer or root authority.
import ../../state/current/logical as current_logical
import ../../state/supplied/services as supplied_services
import ../../codec/state/composition as state_composition
type
  LogicalExportPlan* = object ## Original logical provenance and admitted projection stay paired through source-scope retirement.
    initialized: bool
    logical: CurrentLogicalState
    projection: SuppliedServicesPlan
  LogicalExportError* {.pure.} = enum ## Invalid logical/plan, original projection refusal and defaults expose no usable output prefix.
    Uninitialized, None, InvalidLogical, InvalidPlan, ProjectionFailure
  LogicalExportResult*[T] = object ## Mutable output is available only after complete frozen projection succeeds.
    case status: LogicalExportError
    of None: completed: T
    of ProjectionFailure: projectionReason: SuppliedServicesError
    else: discard # Failed stages carry no partial logical declaration arrays.
func error*[T](outcome: LogicalExportResult[T]): LogicalExportError =
  ## Observe the selected immutable stage only.
  outcome.status
func value*[T](outcome: LogicalExportResult[T]): T {.inline, requires: outcome.status ==
    LogicalExportError.None.} =
  ## Extract only complete admission, copied accounting or detached output.
  outcome.completed
func projectionError*[T](outcome: LogicalExportResult[T]): SuppliedServicesError {.inline,
    requires: outcome.status == LogicalExportError.ProjectionFailure.} =
  ## Preserve original source and independently bounded projection refusal.
  outcome.projectionReason
proc planLogicalExport*(source: CurrentLogicalState,
    limits: SuppliedServicesLimits): LogicalExportResult[LogicalExportPlan] =
  ## Original qualified raw-key provenance supplies complete declarations; no physical map inversion or caller declaration replacement is accepted.
  let original = source.currentLogicalInventory
  if original.error != CurrentLogicalError.None:
    return LogicalExportResult[LogicalExportPlan](status: LogicalExportError.InvalidLogical)
  let planned = planSuppliedServices(original.value, limits)
  if planned.error != SuppliedServicesError.None:
    return LogicalExportResult[LogicalExportPlan](status: LogicalExportError.ProjectionFailure,
        projectionReason: planned.error)
  LogicalExportResult[LogicalExportPlan](status: LogicalExportError.None,
    completed: LogicalExportPlan(initialized: true, logical: source, projection: planned.value))
proc logicalExportInfo*(plan: LogicalExportPlan): LogicalExportResult[SuppliedServicesInfo] =
  ## Copy the exact admitted fact/byte ledger without copying declaration payloads.
  if not plan.initialized: return LogicalExportResult[SuppliedServicesInfo](
      status: LogicalExportError.InvalidPlan)
  LogicalExportResult[SuppliedServicesInfo](status: LogicalExportError.None,
      completed: plan.projection.suppliedServicesPlanInfo.value)
proc executeLogicalExport*(plan: LogicalExportPlan): LogicalExportResult[seq[StateService]] =
  ## Frozen limits and source produce ordinary detached supplied data; output mutation cannot change subsequent exports.
  if not plan.initialized: return LogicalExportResult[seq[StateService]](
      status: LogicalExportError.InvalidPlan)
  let copied = executeSuppliedServices(plan.projection)
  if copied.error != SuppliedServicesError.None:
    return LogicalExportResult[seq[StateService]](status: LogicalExportError.ProjectionFailure,
        projectionReason: copied.error)
  LogicalExportResult[seq[StateService]](status: LogicalExportError.None, completed: copied.value)
