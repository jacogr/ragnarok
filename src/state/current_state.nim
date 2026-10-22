# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate supplied logical declarations against the exact qualified current successor and retain compact inventory.
## This is supplied completeness evidence, not producer-exported provenance, semantic validity or adoption authority.
import ../codec/state_composition
import ./[current_globals, global_snapshot, manifest, inventory]
type
  CurrentStateSerialization* = object ## Private owners bind supplied facts to the original authenticated update and profile.
    initialized: bool
    globals: CurrentGlobalSerialization
    inventory: StateInventory
  CurrentStateError* {.pure.} = enum ## Every refused stage is distinct and grants no successful prefix.
    Uninitialized, None, InvalidGlobals, ManifestFailure, InventoryFailure
  CurrentStateResult*[T] = object ## Private payloads and genuinely failed nested results have separate guarded accessors.
    case status: CurrentStateError
    of None:
      completed: T
    of ManifestFailure:
      manifestReason: StateManifestResult[ValidatedStateManifest]
    of InventoryFailure:
      inventoryReason: StateInventoryResult[StateInventory]
    else:
      discard # Default/invalid owners retain no usable source.
func error*[T](outcome: CurrentStateResult[T]): CurrentStateError =
  ## Observe selection without granting retagging or payload access.
  outcome.status
func value*[T](outcome: CurrentStateResult[T]): T {.inline, requires: outcome.status ==
    CurrentStateError.None.} =
  ## Extract complete success only under checked contracts.
  outcome.completed
func manifestFailure*[T](outcome: CurrentStateResult[T]): StateManifestResult[
    ValidatedStateManifest] {.inline, requires: outcome.status ==
    CurrentStateError.ManifestFailure.} =
  ## Preserve the original mapping, opaque, codec, key and resource refusal.
  outcome.manifestReason
func inventoryFailure*[T](outcome: CurrentStateResult[T]): StateInventoryResult[
    StateInventory] {.inline, requires: outcome.status == CurrentStateError.InventoryFailure.} =
  ## Preserve failed compact-fact admission without manufacturing an empty inventory.
  outcome.inventoryReason
proc qualifyCurrentState*(source: CurrentGlobalSerialization, services: openArray[StateService],
    limits: StateInventoryLimits): CurrentStateResult[CurrentStateSerialization] =
  ## Borrow stable supplied declarations synchronously; existing bounded matching and capture retain detached facts only.
  let globals = source.qualifiedGlobals
  if globals.error != CurrentGlobalsError.None:
    return CurrentStateResult[CurrentStateSerialization](status: CurrentStateError.InvalidGlobals)
  let manifest = validateStateManifest(globals.value, services, limits.manifest)
  if manifest.error != StateManifestError.None:
    return CurrentStateResult[CurrentStateSerialization](status: CurrentStateError.ManifestFailure,
        manifestReason: manifest) # Unmatched or opaque maps never acquire complete logical authority.
  let inventory = captureStateInventory(manifest.value, services, limits)
  if inventory.error != StateInventoryError.None:
    return CurrentStateResult[CurrentStateSerialization](status: CurrentStateError.InventoryFailure,
        inventoryReason: inventory) # A resource refusal cannot become an empty successful inventory.
  CurrentStateResult[CurrentStateSerialization](status: CurrentStateError.None,
    completed: CurrentStateSerialization(initialized: true, globals: source,
        inventory: inventory.value))
proc currentStateGlobals*(source: CurrentStateSerialization): CurrentStateResult[
    CurrentGlobalSerialization] =
  ## Retain the original update, complete globals, derived cardinalities and full child parameters.
  if not source.initialized:
    return CurrentStateResult[CurrentGlobalSerialization](status: CurrentStateError.Uninitialized)
  CurrentStateResult[CurrentGlobalSerialization](status: CurrentStateError.None,
      completed: source.globals)
proc currentStateInventory*(source: CurrentStateSerialization): CurrentStateResult[StateInventory] =
  ## Return immutable compact facts tied to the exact original source; raw storage keys are deliberately not retained here.
  if not source.initialized:
    return CurrentStateResult[StateInventory](status: CurrentStateError.Uninitialized)
  CurrentStateResult[StateInventory](status: CurrentStateError.None, completed: source.inventory)
