# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Import authenticated complete state and publish supplied logical serialization only after complete-root, global, manifest and raw-key qualification all succeed.
import ../proof/[state_import as proof_state_import, view as proof_view]
import ../[store, global_snapshot, manifest]
import ./logical_inventory as supplied_logical_inventory
import ../../codec/state/[trie as state_trie, composition as state_composition]
type
  SuppliedProofImportLimits* = object ## Complete reconstruction, all-global decoding and supplied compact/raw-key retention use independent existing policies.
    restoration*: ProofStateImportLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
  SuppliedProofImportError* {.pure.} = enum ## Every genuine failed stage retains its exact original reason and grants no earlier successful owner.
    Uninitialized, None, RestorationFailure, GlobalFailure, ManifestFailure, LogicalFailure
  SuppliedProofImportResult* = object ## Only all-stage success exposes independently owned complete supplied logical state.
    case status: SuppliedProofImportError
    of None: completed: SuppliedLogicalInventory
    of RestorationFailure: restorationReason: ProofStateImportResult
    of GlobalFailure: globalReason: GlobalStateResult[ValidatedGlobalState]
    of ManifestFailure: manifestReason: StateManifestResult[ValidatedStateManifest]
    of LogicalFailure: logicalReason: SuppliedLogicalResult[SuppliedLogicalInventory]
    else: discard # A refusal never leaks the restored store or an earlier typed prefix.

func error*(outcome: SuppliedProofImportResult): SuppliedProofImportError =
  ## Observe the selected immutable stage without granting a candidate owner.
  outcome.status

func value*(outcome: SuppliedProofImportResult): SuppliedLogicalInventory {.inline,
    requires: outcome.status == SuppliedProofImportError.None.} =
  ## Extract only complete expected-root-bound supplied serialization, never original producer or installation authority.
  outcome.completed

func restorationFailure*(outcome: SuppliedProofImportResult): ProofStateImportResult {.inline,
    requires: outcome.status == SuppliedProofImportError.RestorationFailure.} =
  ## Preserve exact wrong-root, incomplete, resource and complete-store/backend refusal.
  outcome.restorationReason

func globalFailure*(outcome: SuppliedProofImportResult): GlobalStateResult[
    ValidatedGlobalState] {.inline, requires: outcome.status ==
    SuppliedProofImportError.GlobalFailure.} =
  ## Preserve actual global chapter/configuration refusal without its already restored candidate map.
  outcome.globalReason

func manifestFailure*(outcome: SuppliedProofImportResult): StateManifestResult[
    ValidatedStateManifest] {.inline, requires: outcome.status ==
    SuppliedProofImportError.ManifestFailure.} =
  ## Preserve exact complete-map declaration mismatch and namespace refusal.
  outcome.manifestReason

func logicalFailure*(outcome: SuppliedProofImportResult): SuppliedLogicalResult[
    SuppliedLogicalInventory] {.inline, requires: outcome.status ==
    SuppliedProofImportError.LogicalFailure.} =
  ## Preserve actual compact/raw-key capture refusal without successful prefix authority.
  outcome.logicalReason

proc qualifyRestored(restored: ProofStateImportResult, profile: StateProfile,
    services: openArray[StateService], globalLimits: GlobalStateLimits,
    logicalLimits: SuppliedLogicalLimits): SuppliedProofImportResult =
  ## Both restoration paths share the exact atomic typed qualification stages without exposing an earlier successful owner.
  if restored.error != ProofStateImportError.None:
    return SuppliedProofImportResult(status: SuppliedProofImportError.RestorationFailure,
        restorationReason: restored) # Verified subsets must prove completeness before any typed global/source certificate is attempted.
  let globals = validateGlobalState(restored.value.snapshot.value, profile, globalLimits)
  if globals.error != GlobalStateError.None:
    return SuppliedProofImportResult(status: SuppliedProofImportError.GlobalFailure,
        globalReason: globals) # Root equality alone grants no schema validity.
  let manifest = validateStateManifest(globals.value, services, logicalLimits.inventory.manifest)
  if manifest.error != StateManifestError.None:
    return SuppliedProofImportResult(status: SuppliedProofImportError.ManifestFailure,
        manifestReason: manifest) # Explicit complete namespace matching precedes retained raw-key capture.
  let logical = captureSuppliedLogicalInventory(manifest.value, services, logicalLimits)
  if logical.error != SuppliedLogicalError.None:
    return SuppliedProofImportResult(status: SuppliedProofImportError.LogicalFailure,
        logicalReason: logical) # Each independent existing stage keeps its own quota and exact failure; no earlier result escapes.
  SuppliedProofImportResult(status: SuppliedProofImportError.None, completed: logical.value)

type SuppliedProofPageImportLimits* = object ## Delivered pages have independent restoration budgets; typed qualification retains its established all-global and logical policies.
  restoration*: ProofPageImportLimits
  globals*: GlobalStateLimits
  logical*: SuppliedLogicalLimits

proc importSuppliedProofState*(source: ProofView, expected: StateRoot, profile: StateProfile,
    services: openArray[StateService], limits: SuppliedProofImportLimits): SuppliedProofImportResult =
  ## Borrow stable supplied declarations for complete single-view restoration and atomic typed qualification.
  qualifyRestored(importProofState(source, expected, limits.restoration), profile,
      services, limits.globals, limits.logical)

proc importSuppliedProofPages*(pages: openArray[ProofView], expected: StateRoot,
    profile: StateProfile, services: openArray[StateService],
    limits: SuppliedProofPageImportLimits): SuppliedProofImportResult =
  ## Restore arbitrary authenticated pages directly, then expose supplied logical state only after every existing typed stage succeeds.
  qualifyRestored(importProofPages(pages, expected, limits.restoration), profile,
      services, limits.globals, limits.logical)
