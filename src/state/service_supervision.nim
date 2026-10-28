# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Resolve one effective supervisor from a complete immutable service directory under the pinned incarnation rule.
## This source-bound observation does not mutate privileges or replace runtime authorization checks.
import ../codec/state_accounts as codec_state_accounts
import ./inventory as state_inventory
import ./service_directory as state_service_directory

type
  SupervisionDecision* {.pure.} = enum ## Missing or recreated nominees fall back to self without recursive resolution.
    Designated, AbsentNominee, RecreatedNominee
  ServiceSupervisionInfo* = object ## Fixed original identities and the exact creation-slot expectation explain selection.
    service*, designated*, effective*: ServiceIndex
    expectedCreated*: AccountSlot
    decision*: SupervisionDecision
  ServiceSupervision* = object ## Private original directory binds this observation to one complete logical source.
    source: StateServiceDirectory
    info: ServiceSupervisionInfo
  ServiceSupervisionError* {.pure.} = enum ## Missing target is distinct from an absent nominee and invalid provenance.
    Uninitialized, None, InvalidSource, NoService
  ServiceSupervisionResult*[T] = object ## Failed/default selection exposes no invented authority or source.
    case status: ServiceSupervisionError
    of None:
      completed: T
    else:
      discard
func error*[T](outcome: ServiceSupervisionResult[T]): ServiceSupervisionError =
  ## Inspect the immutable success/refusal alternative.
  outcome.status
func value*[T](outcome: ServiceSupervisionResult[T]): T {.inline,
    requires: outcome.status == ServiceSupervisionError.None.} =
  ## Only a genuine complete-source selection exposes its retained observation.
  outcome.completed
proc resolveServiceSupervision*(source: StateServiceDirectory,
    service: ServiceIndex): ServiceSupervisionResult[ServiceSupervision] =
  ## Two bounded binary lookups implement eq:effectivesupervisor without transitive delegation or payload hashing.
  let inventory = source.directoryInventory
  if inventory.error != ServiceDirectoryError.None:
    return ServiceSupervisionResult[ServiceSupervision](
        status: ServiceSupervisionError.InvalidSource) # No default directory grants an absence or authority verdict.
  let target = source.findService(service)
  if target.error == ServiceDirectoryError.NoService:
    return ServiceSupervisionResult[ServiceSupervision](
        status: ServiceSupervisionError.NoService) # The equation is defined only for present targets.
  let row = inventory.value.inventoryServiceAt(target.value).value
  let nominee = source.findService(row.metadata.supervisor)
  var info = ServiceSupervisionInfo(service: service, designated: row.metadata.supervisor,
    effective: service, expectedCreated: row.metadata.supervisorCreated,
    decision: SupervisionDecision.AbsentNominee)
  if nominee.error == ServiceDirectoryError.None:
    let designated = inventory.value.inventoryServiceAt(nominee.value).value
    if uint32(designated.metadata.created) == uint32(row.metadata.supervisorCreated):
      info.effective = row.metadata.supervisor
      info.decision = SupervisionDecision.Designated # Only this exact incarnation receives designated authority.
    else:
      info.decision = SupervisionDecision.RecreatedNominee # Reused identity cannot inherit prior incarnation's authority.
  ServiceSupervisionResult[ServiceSupervision](status: ServiceSupervisionError.None,
    completed: ServiceSupervision(source: source, info: info))
proc supervisionInfo*(selected: ServiceSupervision): ServiceSupervisionResult[
    ServiceSupervisionInfo] =
  ## Copy the completed decision while keeping all source-bearing construction private.
  if selected.source.directoryInfo.error != ServiceDirectoryError.None:
    return ServiceSupervisionResult[ServiceSupervisionInfo](
        status: ServiceSupervisionError.Uninitialized) # Default has no bound decision.
  ServiceSupervisionResult[ServiceSupervisionInfo](status: ServiceSupervisionError.None,
      completed: selected.info)
proc supervisionDirectory*(selected: ServiceSupervision): ServiceSupervisionResult[
    StateServiceDirectory] =
  ## Retain the original complete directory rather than trusting copied identity observations.
  if selected.source.directoryInfo.error != ServiceDirectoryError.None:
    return ServiceSupervisionResult[StateServiceDirectory](
        status: ServiceSupervisionError.Uninitialized) # Default has no retained source.
  ServiceSupervisionResult[StateServiceDirectory](status: ServiceSupervisionError.None,
      completed: selected.source)
