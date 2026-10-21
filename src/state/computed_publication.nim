# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare admitted computed C(10) on the exact authenticated prefix and publish only to its original parent version.

import ../codec/bounded
import ./[computed_admission, report_admission, report_assignments, block_transition,
    block_admission, store]

type
  ComputedPublicationError* {.pure.} = enum ## Ordinary refusals expose no map; only a selected store failure carries its exact cause.
    Uninitialized, None, InvalidSource, LimitExceeded, StateMismatch, StoreFailure
  ComputedPublicationData = ref object ## Immutable acyclic provenance binds the complete hashed successor to its admitted computations.
    source: AdmittedComputedReports
    snapshot: StateStoreSnapshot
  ComputedReportSuccessor* = object ## A prepared implemented-prefix successor is not a full block/finality certificate.
    data: nil ComputedPublicationData
  ComputedPublicationResult*[T] = object ## Success and exact selected store refusal are disjoint private alternatives.
    case status: ComputedPublicationError
    of None:
      completed: T
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Defaults and ordinary refusals retain no successful payload.

func error*[T](outcome: ComputedPublicationResult[T]): ComputedPublicationError =
  ## Observe reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedPublicationResult[T]): T
    {.requires: outcome.status == ComputedPublicationError.None.} =
  ## Preserve successful extraction under optimized compilation.
  outcome.completed
func storeError*[T](outcome: ComputedPublicationResult[T]): StateStoreError
    {.requires: outcome.status == ComputedPublicationError.StoreFailure.} =
  ## Inspect only the actual selected atomic-store refusal.
  outcome.storeReason
proc computedSuccessorSource*(successor: ComputedReportSuccessor): ComputedPublicationResult[
    AdmittedComputedReports] =
  ## Share exact original admission/computation authority; copied metadata cannot replace it.
  let data = successor.data
  if data == nil: return ComputedPublicationResult[AdmittedComputedReports](
      status: ComputedPublicationError.Uninitialized)
  ComputedPublicationResult[AdmittedComputedReports](status: ComputedPublicationError.None,
      completed: data.source)
proc computedSuccessorSnapshot*(successor: ComputedReportSuccessor): ComputedPublicationResult[
    StateStoreSnapshot] =
  ## Share the complete immutable map hashed during preparation, independently of caller mutable handles.
  let data = successor.data
  if data == nil: return ComputedPublicationResult[StateStoreSnapshot](
      status: ComputedPublicationError.Uninitialized)
  ComputedPublicationResult[StateStoreSnapshot](status: ComputedPublicationError.None,
      completed: data.snapshot)
proc prepareComputedPublication*(source: AdmittedComputedReports,
    bytes: ByteLimit): ComputedPublicationResult[ComputedReportSuccessor] =
  ## Preflight the exact retained chapter, then hash its write on a private fork of the genuine staged prefix.
  let selected = source.computedAdmissionReports
  if selected.error != ComputedAdmissionError.None:
    return ComputedPublicationResult[ComputedReportSuccessor](
        status: ComputedPublicationError.InvalidSource)
  let assignments = selected.value.reportAssignments.value
  let length = assignments.reportAssignmentByteLength.value
  if uint64(length) > uint64(bytes):
    return ComputedPublicationResult[ComputedReportSuccessor](
        status: ComputedPublicationError.LimitExceeded)
  let entry = assignments.reportAssignmentEntry.value
  let staged = selected.value.reportBlockStage.value.value
  let forked = forkStateStore(staged.snapshot)
  if forked.error != StateStoreError.None:
    return ComputedPublicationResult[ComputedReportSuccessor](
        status: ComputedPublicationError.StoreFailure, storeReason: forked.error)
  var working = forked.value
  let updated = working.apply([StateWrite(kind: StateWriteKind.Put, key: entry.key,
      value: entry.value)])
  if updated.error != StateStoreError.None:
    return ComputedPublicationResult[ComputedReportSuccessor](
      status: ComputedPublicationError.StoreFailure,
      storeReason: updated.error) # Neither the original parent nor the original prefix handle changed.
  ComputedPublicationResult[ComputedReportSuccessor](status: ComputedPublicationError.None,
    completed: ComputedReportSuccessor(data: ComputedPublicationData(source: source,
        snapshot: updated.value)))
proc publishComputedReports*(state: var StateStore,
    successor: ComputedReportSuccessor): ComputedPublicationResult[StateStoreSnapshot] =
  ## Check exact original parent identity and replace the canonical receiver once; preparation already completed all hashing.
  let data = successor.data
  if data == nil: return ComputedPublicationResult[StateStoreSnapshot](
      status: ComputedPublicationError.InvalidSource)
  let actual = state.snapshot
  if actual.error != StateStoreError.None:
    return ComputedPublicationResult[StateStoreSnapshot](
        status: ComputedPublicationError.StateMismatch)
  let original = data.source.computedAdmissionReports.value.reportBlockStage.value.value.admitted.admittedState
  if not sameStateSnapshot(actual.value, original):
    return ComputedPublicationResult[StateStoreSnapshot](
        status: ComputedPublicationError.StateMismatch)
  let forked = forkStateStore(data.snapshot)
  if forked.error != StateStoreError.None:
    return ComputedPublicationResult[StateStoreSnapshot](
        status: ComputedPublicationError.StoreFailure, storeReason: forked.error)
  state = forked.value # One handle selection publishes the entire authenticated prefix plus its admitted reports.
  ComputedPublicationResult[StateStoreSnapshot](status: ComputedPublicationError.None,
      completed: data.snapshot)
