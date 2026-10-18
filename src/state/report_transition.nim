# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex: atomically publish implemented block stages and new C(10)
## assignments. Accumulation, PVM, other extrinsics and complete block execution remain separate
## stages.
##
## Exposes advanceBlockReports with typed block-stage, report-planning and publication errors.

import ../codec/[block_codec, header, state_layout]
import ./[store, block_admission, block_transition, disputes, safrole_transition, availability,
  report_admission, report_assignments]

type
  ## One explicit collection of bounded policies for the earlier coordinator and complete report admission.
  BlockReportConfig* = object
    admission*: BlockAdmissionConfig
    disputes*: DisputesConfig
    safrole*: SafroleTransitionConfig
    availability*: AvailabilityTransitionConfig
    reports*: ReportAdmissionConfig
  ## Only the selected failed stage carries its cause; no refusal exposes an intermediate map or report plan.
  BlockReportError* {.pure.} = enum
    Uninitialized, None, StageFailure, ReportFailure, PublicationFailure
  ## Success retains certified report/block context and the complete final immutable state snapshot.
  BlockReportUpdate* = object
    reports*: AdmittedReports
    snapshot*: StateStoreSnapshot
  ## Private alternatives prevent construction/retagging of completed updates or unrelated failure reasons.
  BlockReportResult* = object
    case status: BlockReportError
    of None:
      completed: BlockReportUpdate
    of StageFailure:
      stageReason: BlockTransitionResult
    of ReportFailure:
      reportReason: ReportAdmissionResult[AdmittedReports]
    of PublicationFailure:
      publicationReason: StateStoreError
    else:
      discard # Defaults carry neither a candidate nor a usable stage result.

## Inspect stage selection without allowing caller mutation.
func error*(outcome: BlockReportResult): BlockReportError = outcome.status
## Extract a complete immutable update only after every implemented stage and publication succeeds.
func value*(outcome: BlockReportResult): BlockReportUpdate {.inline,
    requires: outcome.status == BlockReportError.None.} = outcome.completed
## Inspect the selected earlier admission/disputes/Safrole/assurance refusal.
func stageError*(outcome: BlockReportResult): BlockTransitionResult {.inline,
    requires: outcome.status == BlockReportError.StageFailure.} = outcome.stageReason
## Inspect the selected report refusal, preserving its own exact child cause.
func reportError*(outcome: BlockReportResult): ReportAdmissionResult[AdmittedReports] {.inline,
    requires: outcome.status == BlockReportError.ReportFailure.} = outcome.reportReason
## Inspect only a refused final store publication's resource/hash cause.
func publicationError*(outcome: BlockReportResult): StateStoreError {.inline,
    requires: outcome.status == BlockReportError.PublicationFailure.} = outcome.publicationReason

## Execute on a private handle, deriving report inputs from its real earlier stage and actual parent binding.
## Replace the caller's canonical handle exactly once, after complete C(10) publication; all earlier failures roll back.
## Older headers are borrowed stably during the call and captured by the report certificate on success.
proc advanceBlockReports*(state: var StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    older: openArray[OwnedHeader], config: BlockReportConfig): BlockReportResult =
  var working = state
  let staged = advanceBlockState(working, candidate, parent, config.admission, config.disputes,
    config.safrole, config.availability)
  if staged.error != BlockTransitionError.None:
    return BlockReportResult(status: BlockReportError.StageFailure,
      stageReason: staged) # The canonical handle still owns every original byte and its root.
  let admitted = planBlockReports(staged, older, config.reports)
  if admitted.error != ReportAdmissionError.None:
    return BlockReportResult(status: BlockReportError.ReportFailure,
      reportReason: admitted) # Even successful disputes, authentication and timeout clearing stay private.
  let entry = admitted.value.reportAssignments.value.reportAssignmentEntry.value
  let original = staged.value.snapshot.lookup(chapterKey(StateChapter(10))).value
  var writes: seq[StateWrite] = @[]
  if original.bytes != entry.value:
    writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put,
      value: entry.value)) # Do not consume write budgets or rehash an unchanged assignment table.
  let published = working.apply(writes)
  if published.error != StateStoreError.None:
    return BlockReportResult(status: BlockReportError.PublicationFailure,
      publicationReason: published.error) # Final map/hash refusal discards every preceding private stage.
  state = working # One handle replacement publishes the entire implemented block prefix atomically.
  BlockReportResult(status: BlockReportError.None,
    completed: BlockReportUpdate(reports: admitted.value, snapshot: published.value))
