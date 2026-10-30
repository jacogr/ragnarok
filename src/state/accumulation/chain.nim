# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Adopt finalized accumulation state and a direct-child chain view only after both private stages succeed.
## Existing aliases retain their owners; publication is single-threaded and has no fallible gap or callbacks.

import ../../chain/[genesis, provider, parameters]
import ../../codec/header
import ../store
import ./[state as accumulation_state, completion as accumulation_completion,
    finalization as accumulation_finalization]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import "../block/admission" as block_admission

type
  AccumulationChainError* {.pure.} = enum ## Each refused stage carries only its selected reason, never a candidate state or view.
    Uninitialized, None, InvalidSource, StateFailure, StaleState, UninitializedView, StaleView,
    ProfileMismatch, ApplicationFailure, HeaderFailure, CaptureFailure, ViewFailure
  AccumulationChainResult* = object ## Success owns the exact child installed in both live handles; failure retains no successful prefix.
    case status: AccumulationChainError
    of None:
      completed: BlockSnapshot
    of StateFailure:
      stateReason: StateStoreError
    of ApplicationFailure:
      applicationReason: AccumulationStateResult
    of HeaderFailure:
      headerReason: HeaderError
    of CaptureFailure:
      captureReason: GenesisError
    of ViewFailure:
      viewReason: ViewAdvanceError
    else:
      discard # Default, invalid, stale and profile alternatives contain neither candidate nor child payload.

func error*(outcome: AccumulationChainResult): AccumulationChainError =
  ## Observe the selected phase without granting mutation of its private discriminator.
  outcome.status

func value*(outcome: AccumulationChainResult): BlockSnapshot {.inline,
    requires: outcome.status == AccumulationChainError.None.} =
  ## Retain only the fully installed child with its exact applied-state version.
  outcome.completed

func stateError*(outcome: AccumulationChainResult): StateStoreError {.inline,
    requires: outcome.status == AccumulationChainError.StateFailure.} =
  ## Inspect only a failed target snapshot lookup.
  outcome.stateReason

func applicationFailure*(outcome: AccumulationChainResult): AccumulationStateResult {.inline,
    requires: outcome.status == AccumulationChainError.ApplicationFailure.} =
  ## Preserve the actual failed state application and its guarded nested phase reasons.
  outcome.applicationReason

func headerError*(outcome: AccumulationChainResult): HeaderError {.inline,
    requires: outcome.status == AccumulationChainError.HeaderFailure.} =
  ## Inspect only a failed admitted-header metadata or encoding operation.
  outcome.headerReason

func captureError*(outcome: AccumulationChainResult): GenesisError {.inline,
    requires: outcome.status == AccumulationChainError.CaptureFailure.} =
  ## Inspect only a failed structural child capture, with no partially retained child.
  outcome.captureReason

func viewError*(outcome: AccumulationChainResult): ViewAdvanceError {.inline,
    requires: outcome.status == AccumulationChainError.ViewFailure.} =
  ## Inspect only an actual failed direct-child append.
  outcome.viewReason

proc applyAccumulationChain*(state: var StateStore, view: var ChainView,
    source: PreparedFinalAccumulation, limits: AccumulationCompositionLimits): AccumulationChainResult =
  ## Privately apply, capture the source's own header and append; publish both handles only after full success.
  let parent = source.finalAccumulationParent
  if parent.error != AccumulationFinalizationError.None:
    return AccumulationChainResult(status: AccumulationChainError.InvalidSource) # Defaults authorize no target inspection.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return AccumulationChainResult(status: AccumulationChainError.StateFailure,
      stateReason: current.error) # No implicit empty target is synthesized.
  if not sameStateSnapshot(current.value, parent.value):
    return AccumulationChainResult(status: AccumulationChainError.StaleState) # Replay and equal-root reconstructions fail before composition.
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return AccumulationChainResult(status: AccumulationChainError.UninitializedView) # An explicit selected parent is mandatory.
  if not sameStateSnapshot(head.value.stateSnapshot, parent.value):
    return AccumulationChainResult(status: AccumulationChainError.StaleView) # A matching root cannot replace retained parent identity.
  let reports = source.finalAccumulationAdmission.value
  if reports.requiresFuzzView and not view.fuzzOnly:
    return AccumulationChainResult(status: AccumulationChainError.ProfileMismatch) # Test-seed facts cannot authorize a production chain.
  let admission = reports.reportBlockStage.value
  let profile = admission.blockTransitionProfile
  if uint64(profile.cores) != uint64(head.value.cores) or
      uint64(profile.epochSlots) != uint64(head.value.epochSlots) or
      uint64(profile.validators) != uint64(head.value.activeValidators):
    return AccumulationChainResult(status: AccumulationChainError.ProfileMismatch) # Preserve the authenticated header decoding domains.
  var working = state
  let applied = applyAccumulationState(working, source, limits)
  if applied.error != AccumulationStateError.None:
    return AccumulationChainResult(status: AccumulationChainError.ApplicationFailure,
      applicationReason: applied) # A successful state prefix remains private if any later phase refuses.
  let ownedHeader = admission.value.admitted.admittedHeader
  let info = ownedHeader.headerInfo
  if info.error != HeaderError.None:
    return AccumulationChainResult(status: AccumulationChainError.HeaderFailure,
      headerReason: info.error) # Never infer an empty sealed header from absent metadata.
  if info.value.consumed > 256 * 1024:
    return AccumulationChainResult(status: AccumulationChainError.CaptureFailure,
      captureReason: GenesisError.Invalid) # Bound serialization before allocating under chain capture's fixed ceiling.
  var wire = newSeq[byte](info.value.consumed)
  let encoded = encodeOwnedHeader(ownedHeader, wire)
  if encoded.error != HeaderError.None:
    return AccumulationChainResult(status: AccumulationChainError.HeaderFailure,
      headerReason: encoded.error) # No encoded prefix or partly applied state escapes.
  let captured = captureBlockSnapshot(wire, applied.value, head.value.chainParameters)
  let child = if captured.error == GenesisError.None:
    withBlockBody(captured.value, admission.value.admitted.admittedBlock)
    else: captured # Body retention failure stays private alongside the already prepared state.
  if child.error != GenesisError.None:
    return AccumulationChainResult(status: AccumulationChainError.CaptureFailure,
      captureReason: child.error) # Late native hash or structural refusal leaves both live handles intact.
  let advanced = view.advanceView(child)
  if advanced.error != ViewAdvanceError.None:
    return AccumulationChainResult(status: AccumulationChainError.ViewFailure,
      viewReason: advanced.error) # Even fully composed/captured state stays private on a failed append.
  state = working # No fallible work or user callbacks occurs between these single-threaded replacements.
  view = advanced.value
  AccumulationChainResult(status: AccumulationChainError.None, completed: child.value)
