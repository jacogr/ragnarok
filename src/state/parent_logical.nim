# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Seed complete supplied logical inventory on the original selected configured parent, retaining full history/Parameters/finality provenance.
## Startup parent description is not a completed transition or producer-exported mutation certificate.
import ../codec/state_composition
import ./[parent_globals, global_snapshot, manifest, supplied_logical_inventory]
type
  SelectedLogicalParent* = object ## Private original selected-global owner and revalidated logical inventory cannot be paired unchecked.
    initialized: bool
    source: SelectedParentGlobals
    logical: SuppliedLogicalInventory
  ParentLogicalError* {.pure.} = enum ## Default/invalid selection, exact-map matching and bounded logical capture are distinct stages.
    Uninitialized, None, InvalidGlobals, ManifestFailure, LogicalFailure
  ParentLogicalResult*[T] = object ## Private alternatives retain genuinely failed nested reasons with no successful prefix.
    case status: ParentLogicalError
    of None:
      completed: T
    of ManifestFailure:
      manifestReason: StateManifestResult[ValidatedStateManifest]
    of LogicalFailure:
      logicalReason: SuppliedLogicalResult[SuppliedLogicalInventory]
    else:
      discard # No default or failed result grants a configured logical parent.
func error*[T](outcome: ParentLogicalResult[T]): ParentLogicalError =
  ## Observe selected immutable alternatives only.
  outcome.status
func value*[T](outcome: ParentLogicalResult[T]): T {.inline, requires: outcome.status ==
    ParentLogicalError.None.} =
  ## Extract only complete initialized parent evidence or retained original source owners.
  outcome.completed
func manifestFailure*[T](outcome: ParentLogicalResult[T]): StateManifestResult[
    ValidatedStateManifest] {.inline, requires: outcome.status ==
    ParentLogicalError.ManifestFailure.} =
  ## Preserve original missing/extra/opaque/duplicate/malformed/resource matching refusals.
  outcome.manifestReason
func logicalFailure*[T](outcome: ParentLogicalResult[T]): SuppliedLogicalResult[
    SuppliedLogicalInventory] {.inline, requires: outcome.status ==
    ParentLogicalError.LogicalFailure.} =
  ## Preserve only the actual failed bounded raw-key/compact capture stage.
  outcome.logicalReason
proc captureLogicalParent*(source: SelectedParentGlobals, services: openArray[StateService],
    limits: SuppliedLogicalLimits): ParentLogicalResult[SelectedLogicalParent] =
  ## Match stable borrowed complete declarations to the original selected source, then retain detached raw keys and compact identities.
  let globals = source.parentGlobals
  if globals.error != ParentGlobalsError.None:
    return ParentLogicalResult[SelectedLogicalParent](status: ParentLogicalError.InvalidGlobals)
  let manifest = validateStateManifest(globals.value, services, limits.inventory.manifest)
  if manifest.error != StateManifestError.None:
    return ParentLogicalResult[SelectedLogicalParent](status: ParentLogicalError.ManifestFailure,
        manifestReason: manifest) # No stripped/equal-root replacement map can satisfy original selected parent coverage.
  let logical = captureSuppliedLogicalInventory(manifest.value, services, limits)
  if logical.error != SuppliedLogicalError.None:
    return ParentLogicalResult[SelectedLogicalParent](status: ParentLogicalError.LogicalFailure,
        logicalReason: logical) # No successful partial raw-key owner escapes a late admission or revalidation failure.
  ParentLogicalResult[SelectedLogicalParent](status: ParentLogicalError.None,
      completed: SelectedLogicalParent(initialized: true, source: source, logical: logical.value))
proc logicalParentGlobals*(source: SelectedLogicalParent): ParentLogicalResult[
    SelectedParentGlobals] =
  ## Retain original selected view/profile/full Parameters/finality, without inventing completed execution authority.
  if not source.initialized:
    return ParentLogicalResult[SelectedParentGlobals](status: ParentLogicalError.Uninitialized)
  ParentLogicalResult[SelectedParentGlobals](status: ParentLogicalError.None,
      completed: source.source)
proc logicalParentInventory*(source: SelectedLogicalParent): ParentLogicalResult[
    SuppliedLogicalInventory] =
  ## Retain complete supplied logical identities and raw keys tied to the exact original physical head.
  if not source.initialized:
    return ParentLogicalResult[SuppliedLogicalInventory](status: ParentLogicalError.Uninitialized)
  ParentLogicalResult[SuppliedLogicalInventory](status: ParentLogicalError.None,
      completed: source.logical)
