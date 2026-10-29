# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded whole-service economic observations retain certified footprints, exact directory and explicit valid parameters.
## Undercoverage is reported as an observation; no new global account funding or root-authority rule is inferred.
import ../codec/bounded
import ../codec/state/accounts as state_accounts
import ./[inventory, footprint_audit]
import ./service/directory as service_directory
import ./economic_profile
import ./service/deposit as service_deposit

type
  EconomicsTableLimits* = object ## All service observations and retained native fixed rows are bounded before allocation.
    services*: ElementLimit
    bytes*: ByteLimit
  EconomicsTableInfo* = object ## Coverage counts describe this explicit parameter choice, not valid-state acceptance.
    services*, covered*, uncovered*: int
    retainedBytes*: uint64
  EconomicsTableData = ref object # One acyclic owner retains original evidence/configuration and fixed rows only.
    footprints: CheckedAccountFootprints
    directory: StateServiceDirectory
    profile: StateEconomicProfile
    rows: seq[ServiceDepositInfo]
    info: EconomicsTableInfo
  StateEconomicsTable* = object ## Private whole-source economic batch has no mutable runtime/account state.
    data: nil EconomicsTableData
  EconomicsTableError* {.pure.} = enum ## Invalid policy/evidence, substitution, bounded refusal and late observation failure remain distinct.
    Uninitialized, None, InvalidFootprints, InvalidDirectory, InvalidProfile, SourceMismatch,
      LimitExceeded, ObservationFailure, NoService, InvalidIndex
  EconomicsTableResult*[T] = object ## No partial row table escapes a late arithmetic or source-bound observation refusal.
    case status: EconomicsTableError
    of None:
      completed: T
    of ObservationFailure:
      reason: ServiceDepositResult[ServiceDepositObservation]
      service: ServiceIndex
      ordinal: InventoryServiceIndex
    else:
      discard
func error*[T](outcome: EconomicsTableResult[T]): EconomicsTableError =
  ## Inspect the immutable selected alternative.
  outcome.status
func value*[T](outcome: EconomicsTableResult[T]): T {.inline,
    requires: outcome.status == EconomicsTableError.None.} =
  ## Failed/default batches expose no completed source-bearing owner.
  outcome.completed
func observationFailure*[T](outcome: EconomicsTableResult[T]): ServiceDepositResult[
    ServiceDepositObservation] {.inline,

requires: outcome.status == EconomicsTableError.ObservationFailure.} =
  ## Preserve the genuinely failed row result, including guarded nested arithmetic reason.
  outcome.reason
func failedService*[T](outcome: EconomicsTableResult[T]): ServiceIndex {.inline,
    requires: outcome.status == EconomicsTableError.ObservationFailure.} =
  ## Only an actual failed observation identifies an offending service.
  outcome.service
func failedOrdinal*[T](outcome: EconomicsTableResult[T]): InventoryServiceIndex {.inline,
    requires: outcome.status == EconomicsTableError.ObservationFailure.} =
  ## Preserve the original inventory ordinal without granting a successful prefix.
  outcome.ordinal
proc buildEconomicsTable*(footprints: CheckedAccountFootprints,
    directory: StateServiceDirectory, profile: StateEconomicProfile,
    limits: EconomicsTableLimits): EconomicsTableResult[StateEconomicsTable] =
  ## Validate exact provenance/configuration and preflight all retained rows before computing observations.
  let source = footprints.footprintInventory
  if source.error != FootprintAuditError.None:
    return EconomicsTableResult[StateEconomicsTable](
        status: EconomicsTableError.InvalidFootprints) # No default dependent metadata evidence.
  let indexed = directory.directoryInventory
  if indexed.error != ServiceDirectoryError.None:
    return EconomicsTableResult[StateEconomicsTable](
        status: EconomicsTableError.InvalidDirectory) # No default complete enumeration.
  let schedule = profile.economicSchedule
  if schedule.error != EconomicProfileError.None:
    return EconomicsTableResult[StateEconomicsTable](
        status: EconomicsTableError.InvalidProfile) # Do not substitute default zero rates.
  if not sameStateInventory(source.value, indexed.value):
    return EconomicsTableResult[StateEconomicsTable](
        status: EconomicsTableError.SourceMismatch) # Equal separately captured sources cannot join evidence.
  let count = source.value.inventoryInfo.value.services
  if uint64(count) > uint64(limits.services) or uint64(count) > min(uint64(limits.bytes), uint64(
      high(int))) div uint64(sizeof(ServiceDepositInfo)):
    return EconomicsTableResult[StateEconomicsTable](
        status: EconomicsTableError.LimitExceeded) # Prove native fixed-row allocation extent before any output construction.
  var rows = newSeq[ServiceDepositInfo](count)
  var info = EconomicsTableInfo(services: count, retainedBytes: uint64(count) * uint64(sizeof(
      ServiceDepositInfo)))
  for i in 0..<count:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = source.value.inventoryServiceAt(ordinal).value
    let selected = observeServiceDeposit(footprints, directory, row.service, schedule.value)
    if selected.error != ServiceDepositError.None:
      return EconomicsTableResult[StateEconomicsTable](
        status: EconomicsTableError.ObservationFailure,
        reason: selected, service: row.service, ordinal: ordinal) # Previously computed rows retire without a prefix certificate.
    rows[i] = selected.value.serviceDepositInfo.value
    if rows[i].covered:
      info.covered += 1 # At most one bounded counter increment per completed service.
    else:
      info.uncovered += 1 # Undercoverage is an ordinary explicit economic observation.
  EconomicsTableResult[StateEconomicsTable](status: EconomicsTableError.None,
    completed: StateEconomicsTable(data: EconomicsTableData(footprints: footprints,
      directory: directory,
      profile: profile, rows: rows, info: info)))
proc economicTableInfo*(table: StateEconomicsTable): EconomicsTableResult[EconomicsTableInfo] =
  ## Copy or retain the original completed info without exposing mutable table storage.
  let data = table.data
  if data == nil:
    return EconomicsTableResult[EconomicsTableInfo](
        status: EconomicsTableError.Uninitialized) # Default table has no completed source.
  EconomicsTableResult[EconomicsTableInfo](status: EconomicsTableError.None, completed: data.info)
proc economicTableFootprints*(table: StateEconomicsTable): EconomicsTableResult[
    CheckedAccountFootprints] =
  ## Copy or retain the original completed footprints without exposing mutable table storage.
  let data = table.data
  if data == nil:
    return EconomicsTableResult[CheckedAccountFootprints](
        status: EconomicsTableError.Uninitialized) # Default table has no completed source.
  EconomicsTableResult[CheckedAccountFootprints](status: EconomicsTableError.None,
      completed: data.footprints)
proc economicTableDirectory*(table: StateEconomicsTable): EconomicsTableResult[
    StateServiceDirectory] =
  ## Copy or retain the original completed directory without exposing mutable table storage.
  let data = table.data
  if data == nil:
    return EconomicsTableResult[StateServiceDirectory](
        status: EconomicsTableError.Uninitialized) # Default table has no completed source.
  EconomicsTableResult[StateServiceDirectory](status: EconomicsTableError.None,
      completed: data.directory)
proc economicTableProfile*(table: StateEconomicsTable): EconomicsTableResult[StateEconomicProfile] =
  ## Copy or retain the original completed profile without exposing mutable table storage.
  let data = table.data
  if data == nil:
    return EconomicsTableResult[StateEconomicProfile](
        status: EconomicsTableError.Uninitialized) # Default table has no completed source.
  EconomicsTableResult[StateEconomicProfile](status: EconomicsTableError.None,
      completed: data.profile)
proc economicTableAt*(table: StateEconomicsTable,
    ordinal: InventoryServiceIndex): EconomicsTableResult[ServiceDepositInfo] =
  ## Validate the complete unsigned original-order ordinal before narrowing to the retained fixed row.
  let data = table.data
  if data == nil:
    return EconomicsTableResult[ServiceDepositInfo](status: EconomicsTableError.Uninitialized) # No default rows.
  if uint64(ordinal) >= uint64(data.rows.len):
    return EconomicsTableResult[ServiceDepositInfo](
        status: EconomicsTableError.InvalidIndex) # No truncating coordinate conversion.
  EconomicsTableResult[ServiceDepositInfo](status: EconomicsTableError.None, completed: data.rows[
      int(uint64(ordinal))])
proc economicsFor*(table: StateEconomicsTable, service: ServiceIndex): EconomicsTableResult[
    ServiceDepositInfo] =
  ## Bounded identity lookup selects the completed original-order observation or proves service absence.
  let data = table.data
  if data == nil:
    return EconomicsTableResult[ServiceDepositInfo](
        status: EconomicsTableError.Uninitialized) # Missing provenance is not absence.
  let found = data.directory.findService(service)
  if found.error == ServiceDirectoryError.NoService:
    return EconomicsTableResult[ServiceDepositInfo](
        status: EconomicsTableError.NoService) # Complete-source target absence.
  table.economicTableAt(found.value)
