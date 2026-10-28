# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound deposit observations use certified footprints and complete same-inventory service lookup.
## Caller-selected rates and insufficient coverage are observations, never automatic valid-state or root authority.
import ../codec/state_accounts as codec_state_accounts
import ./inventory as state_inventory
import ./service_directory as state_service_directory
import ./footprint_audit as state_footprint_audit
import ./account_footprint as state_account_footprint
import ./account_deposit as state_account_deposit

type
  ServiceDepositInfo* = object ## Copied nominal inputs and computed threshold explain one explicit economic observation.
    service*: ServiceIndex
    footprint*: AccountFootprint
    schedule*: AccountDepositSchedule
    gratis*, liquid*, protected*, minimum*: AccountBalance
    covered*: bool
  ServiceDepositObservation* = object ## Private exact inputs bind the observation to certified complete-source metadata.
    footprints: CheckedAccountFootprints
    directory: StateServiceDirectory
    info: ServiceDepositInfo
  ServiceDepositError* {.pure.} = enum ## Invalid evidence, cross-owner substitution, missing target and arithmetic refusal are distinct.
    Uninitialized, None, InvalidFootprints, InvalidDirectory, SourceMismatch, NoService, ArithmeticFailure
  ServiceDepositResult*[T] = object ## Failed/default queries expose no partial observation or retained success owner.
    case status: ServiceDepositError
    of None:
      completed: T
    of ArithmeticFailure:
      reason: AccountDepositError
    else:
      discard
func error*[T](outcome: ServiceDepositResult[T]): ServiceDepositError =
  ## Inspect the immutable alternative.
  outcome.status
func value*[T](outcome: ServiceDepositResult[T]): T {.inline,
    requires: outcome.status == ServiceDepositError.None.} =
  ## Only complete evidence-bound queries expose an economic observation.
  outcome.completed
func arithmeticError*[T](outcome: ServiceDepositResult[T]): AccountDepositError {.inline,
    requires: outcome.status == ServiceDepositError.ArithmeticFailure.} =
  ## Inspect only a real unrepresentable threshold refusal.
  outcome.reason
proc observeServiceDeposit*(footprints: CheckedAccountFootprints,
    directory: StateServiceDirectory, service: ServiceIndex,
    schedule: AccountDepositSchedule): ServiceDepositResult[ServiceDepositObservation] =
  ## Constant fixed work plus one bounded binary lookup uses certified original metadata without payload copies or hashes.
  let source = footprints.footprintInventory
  if source.error != FootprintAuditError.None:
    return ServiceDepositResult[ServiceDepositObservation](
        status: ServiceDepositError.InvalidFootprints) # No default dependent-field evidence.
  let indexed = directory.directoryInventory
  if indexed.error != ServiceDirectoryError.None:
    return ServiceDepositResult[ServiceDepositObservation](
        status: ServiceDepositError.InvalidDirectory) # No default complete service enumeration.
  if not sameStateInventory(source.value, indexed.value):
    return ServiceDepositResult[ServiceDepositObservation](
        status: ServiceDepositError.SourceMismatch) # Equal snapshots cannot substitute a separate logical capture.
  let found = directory.findService(service)
  if found.error == ServiceDirectoryError.NoService:
    return ServiceDepositResult[ServiceDepositObservation](
        status: ServiceDepositError.NoService) # Complete-source absence grants no fabricated zero-footprint account.
  let row = source.value.inventoryServiceAt(found.value).value
  let footprint = footprints.checkedFootprintAt(found.value).value
  let minimum = calculateAccountMinimum(footprint, row.metadata.depositOffset, schedule)
  if minimum.error != AccountDepositError.None:
    return ServiceDepositResult[ServiceDepositObservation](
      status: ServiceDepositError.ArithmeticFailure,
      reason: minimum.error) # Preserve mathematical representability independently of account coverage.
  ServiceDepositResult[ServiceDepositObservation](status: ServiceDepositError.None,
    completed: ServiceDepositObservation(footprints: footprints, directory: directory,
      info: ServiceDepositInfo(service: service, footprint: footprint, schedule: schedule,
        gratis: row.metadata.depositOffset, liquid: row.metadata.balance,
        protected: row.metadata.supervisorBalance, minimum: minimum.value,
        covered: coversAccountMinimum(row.metadata.balance, row.metadata.supervisorBalance,
            minimum.value))))
proc serviceDepositInfo*(observation: ServiceDepositObservation): ServiceDepositResult[
    ServiceDepositInfo] =
  ## Copy a completed economic observation without exposing mutable construction authority.
  if observation.footprints.footprintInfo.error != FootprintAuditError.None:
    return ServiceDepositResult[ServiceDepositInfo](
        status: ServiceDepositError.Uninitialized) # Default carries no source.
  ServiceDepositResult[ServiceDepositInfo](status: ServiceDepositError.None,
      completed: observation.info)
proc depositFootprints*(observation: ServiceDepositObservation): ServiceDepositResult[
    CheckedAccountFootprints] =
  ## Retain the original certified dependent-field owner.
  if observation.footprints.footprintInfo.error != FootprintAuditError.None:
    return ServiceDepositResult[CheckedAccountFootprints](
        status: ServiceDepositError.Uninitialized) # No default evidence.
  ServiceDepositResult[CheckedAccountFootprints](status: ServiceDepositError.None,
      completed: observation.footprints)
proc depositDirectory*(observation: ServiceDepositObservation): ServiceDepositResult[
    StateServiceDirectory] =
  ## Retain the original same-inventory service lookup owner.
  if observation.footprints.footprintInfo.error != FootprintAuditError.None:
    return ServiceDepositResult[StateServiceDirectory](
        status: ServiceDepositError.Uninitialized) # No default directory.
  ServiceDepositResult[StateServiceDirectory](status: ServiceDepositError.None,
      completed: observation.directory)
