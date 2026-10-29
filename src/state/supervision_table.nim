# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded whole-source supervision observations reuse complete-directory incarnation checks.
## Failed batch construction exposes no prefix table or selected authority.
import ../codec/bounded
import ../codec/state/accounts as state_accounts
import ./inventory
import ./service/[directory as service_directory, supervision as service_supervision]

type
  SupervisionTableLimits* = object ## Service resolution work and retained native fixed-row bytes are independently bounded.
    services*: ElementLimit
    bytes*: ByteLimit
  SupervisionTableInfo* = object ## Each row has one decision; all counters are bounded by the completed service count.
    services*, designated*, absent*, recreated*: int
    retainedBytes*: uint64
  SupervisionTableData = ref object # Immutable observation rows retain only one original complete directory.
    source: StateServiceDirectory
    rows: seq[ServiceSupervisionInfo]
    info: SupervisionTableInfo
  StateSupervisionTable* = object ## A complete source-bound batch, not mutable runtime privilege state.
    data: nil SupervisionTableData
  SupervisionTableError* {.pure.} = enum ## Default, bounded refusal, absent target and nested resolution failure remain distinct.
    Uninitialized, None, InvalidSource, LimitExceeded, ResolutionFailure, NoService, InvalidIndex
  SupervisionTableResult*[T] = object ## Only complete success exposes the table or copied fixed observations.
    case status: SupervisionTableError
    of None:
      completed: T
    of ResolutionFailure:
      reason: ServiceSupervisionError
    else:
      discard
func error*[T](outcome: SupervisionTableResult[T]): SupervisionTableError =
  ## Read the immutable selected alternative.
  outcome.status
func value*[T](outcome: SupervisionTableResult[T]): T {.inline,
    requires: outcome.status == SupervisionTableError.None.} =
  ## No default or failed batch grants a complete source-bearing table.
  outcome.completed
func resolutionError*[T](outcome: SupervisionTableResult[T]): ServiceSupervisionError {.inline,
    requires: outcome.status == SupervisionTableError.ResolutionFailure.} =
  ## Inspect only an actual failed row resolver rather than an invented default reason.
  outcome.reason
proc buildSupervisionTable*(source: StateServiceDirectory,
    limits: SupervisionTableLimits): SupervisionTableResult[StateSupervisionTable] =
  ## Preflight all resolution count and retained allocation before constructing fixed output rows.
  let directory = source.directoryInfo
  if directory.error != ServiceDirectoryError.None:
    return SupervisionTableResult[StateSupervisionTable](
        status: SupervisionTableError.InvalidSource) # Default is not a complete empty directory.
  let count = uint64(directory.value.services)
  if count > uint64(limits.services) or count > min(uint64(limits.bytes), uint64(high(
      int))) div uint64(sizeof(ServiceSupervisionInfo)):
    return SupervisionTableResult[StateSupervisionTable](
        status: SupervisionTableError.LimitExceeded) # Prove native allocation multiplication without overflow.
  let inventory = source.directoryInventory.value
  var rows = newSeq[ServiceSupervisionInfo](directory.value.services)
  var info = SupervisionTableInfo(services: directory.value.services,
    retainedBytes: count * uint64(sizeof(ServiceSupervisionInfo)))
  for i in 0..<rows.len:
    let row = inventory.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    let selected = resolveServiceSupervision(source, row.service)
    if selected.error != ServiceSupervisionError.None:
      return SupervisionTableResult[StateSupervisionTable](
        status: SupervisionTableError.ResolutionFailure,
        reason: selected.error) # Never publish earlier rows if a source resolver refuses later.
    rows[i] = selected.value.supervisionInfo.value
    case rows[i].decision
    of SupervisionDecision.Designated: info.designated += 1 # At most one counter increment per bounded service.
    of SupervisionDecision.AbsentNominee: info.absent +=
        1 # Exhaustive absence belongs to the complete input source.
    of SupervisionDecision.RecreatedNominee: info.recreated +=
        1 # Preserve incarnation failure without rejecting specified fallback.
  SupervisionTableResult[StateSupervisionTable](status: SupervisionTableError.None,
    completed: StateSupervisionTable(data: SupervisionTableData(source: source, rows: rows, info: info)))
proc supervisionTableInfo*(table: StateSupervisionTable): SupervisionTableResult[
    SupervisionTableInfo] =
  ## Copy completed batch accounting without exposing backing rows.
  let data = table.data
  if data == nil:
    return SupervisionTableResult[SupervisionTableInfo](
        status: SupervisionTableError.Uninitialized) # No default table.
  SupervisionTableResult[SupervisionTableInfo](status: SupervisionTableError.None,
      completed: data.info)
proc supervisionTableDirectory*(table: StateSupervisionTable): SupervisionTableResult[
    StateServiceDirectory] =
  ## Retain the original complete source directory for exact provenance checks.
  let data = table.data
  if data == nil:
    return SupervisionTableResult[StateServiceDirectory](
        status: SupervisionTableError.Uninitialized) # No default source.
  SupervisionTableResult[StateServiceDirectory](status: SupervisionTableError.None,
      completed: data.source)
proc supervisionTableAt*(table: StateSupervisionTable,
    ordinal: InventoryServiceIndex): SupervisionTableResult[ServiceSupervisionInfo] =
  ## Original capture order selects fixed decisions only after full-width bounds validation.
  let data = table.data
  if data == nil:
    return SupervisionTableResult[ServiceSupervisionInfo](
        status: SupervisionTableError.Uninitialized) # No default rows.
  if uint64(ordinal) >= uint64(data.rows.len):
    return SupervisionTableResult[ServiceSupervisionInfo](
        status: SupervisionTableError.InvalidIndex) # Never narrow an unchecked original ordinal.
  SupervisionTableResult[ServiceSupervisionInfo](status: SupervisionTableError.None,
      completed: data.rows[int(uint64(ordinal))])
proc supervisionFor*(table: StateSupervisionTable,
    service: ServiceIndex): SupervisionTableResult[ServiceSupervisionInfo] =
  ## Resolve a present identity through the retained complete directory and return its original-order row.
  let data = table.data
  if data == nil:
    return SupervisionTableResult[ServiceSupervisionInfo](
        status: SupervisionTableError.Uninitialized) # Missing provenance is not absence.
  let found = data.source.findService(service)
  if found.error == ServiceDirectoryError.NoService:
    return SupervisionTableResult[ServiceSupervisionInfo](
        status: SupervisionTableError.NoService) # Complete-source proven target absence.
  table.supervisionTableAt(found.value)
