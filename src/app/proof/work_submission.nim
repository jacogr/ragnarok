# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed two-stage work-submission CPU jobs retain original complete-state provenance under the shared graph lease.
## All aliases, including completed authorization and refinement, remain untouched until exact collection or joined stop.
import ../../jamnp-s/work_submission
import ../../jamnp-s/work_duty
import ../../jamnp-s/work_report
from ../../state/computed/guarantee import ComputedGuaranteeTranscript
from ../../codec/work/report import ErasureShards
import ../../state/[store, input_refinement]
import "../../state/import/inputs" as import_inputs
import "../../state/import/justification" as import_justification
import ../../codec/work/report as work_report
import ../../chain/parameters

type
  WorkJobError* {.pure.} = enum ## Local capture refusals contain no source-bearing input capability.
    Uninitialized, None, InvalidInput, LimitExceeded
  WorkJobResultKind* {.pure.} = enum ## A completed CPU turn exposes only its selected full success or genuine child failure.
    Uninitialized, Authorized, Refined, AuthorizationFailure, BodyFailure, RefinementFailure,
      DutyFailure, Reported, ReportFailure
  WorkSource = ref object ## Immutable acyclic provenance retains the exact original complete map, package header and policy.
    header: WorkSubmissionHeader
    state: StateStoreSnapshot
    parameters: Parameters
    limits: WorkSubmissionLimits
    execution: InputRefinementLimits
    recipient: WorkRecipient
    dutyLimits: WorkDutyLimits
  WorkContextData = ref object ## A real successful grant cannot be rebound to another source or execution policy.
    source: WorkSource
    grant: AuthorizedWorkSubmission
    duty: WorkDuty
  AuthorizedWorkContext* = object ## Only a successful private CPU capability can construct a usable context.
    data: nil WorkContextData
  WorkJobResult* = object ## Failed/default results expose no input, grant, partial refinement or unrelated child.
    case status: WorkJobResultKind
    of Reported: report: ComputedGuaranteeTranscript
    of ReportFailure: reportReason: WorkReportResult
    of DutyFailure: dutyReason: WorkDutyResult[WorkDuty]
    of Authorized: context: AuthorizedWorkContext
    of Refined: execution: InputRefinement
    of AuthorizationFailure: authorizationReason: WorkSubmissionResult[AuthorizedWorkSubmission]
    of BodyFailure: bodyReason: WorkSubmissionResult[VerifiedImportInputs]
    of RefinementFailure: refinementReason: InputRefinementResult[InputRefinement]
    else: discard # Defaults contain neither selected-state ownership nor an invented success.
  WorkRunner = proc(data: WorkJobData): WorkJobResult {.nimcall.}
    ## Closed capability is bound only to the actual implementation in this module.
  WorkJobData = ref object ## Detached bounded bytes accompany immutable selected-state owners; no stream pointer crosses the CPU boundary.
    run: nil WorkRunner
    source: WorkSource
    context: AuthorizedWorkContext
    refined: InputRefinement
    shards: ErasureShards
    reportLimits: WorkReportLimits
    extrinsics, segments, proofs: seq[byte]
    imports: seq[seq[VerifiedImport]]
    lookup: seq[SegmentLookup]
  WorkSubmissionJob* = object ## Default jobs have no executable source or private runner.
    data: nil WorkJobData
  WorkJobAdmission* = object ## Only complete capture carries an executable job.
    case status: WorkJobError
    of None: completed: WorkSubmissionJob
    else: discard            # No captured prefix escapes refusal.
func error*(outcome: WorkJobAdmission): WorkJobError =
  ## Inspect local capture status before selecting a job.
  outcome.status
func value*(outcome: WorkJobAdmission): WorkSubmissionJob {.requires: outcome.status ==
    WorkJobError.None.} =
  ## Capture grants execution-input authority, never successful authorization or refinement.
  outcome.completed
func kind*(outcome: WorkJobResult): WorkJobResultKind =
  ## Scalar observations retain no canonical graph alias.
  outcome.status
func context*(outcome: WorkJobResult): AuthorizedWorkContext {.requires: outcome.status ==
    WorkJobResultKind.Authorized.} =
  ## Retain the original authorization context only while the host owns the shared graph lease.
  outcome.context
func execution*(outcome: WorkJobResult): InputRefinement {.requires: outcome.status ==
    WorkJobResultKind.Refined.} =
  ## Only genuine complete refinement exposes its original immutable execution owner.
  outcome.execution
func authorizationError*(outcome: WorkJobResult): WorkSubmissionResult[
    AuthorizedWorkSubmission] {.requires: outcome.status ==
    WorkJobResultKind.AuthorizationFailure.} =
  ## Preserve the exact real failed admission result and its guarded child details.
  outcome.authorizationReason
func bodyError*(outcome: WorkJobResult): WorkSubmissionResult[
    VerifiedImportInputs] {.requires: outcome.status == WorkJobResultKind.BodyFailure.} =
  ## No successfully verified prefix can be extracted from body refusal.
  outcome.bodyReason
func refinementError*(outcome: WorkJobResult): InputRefinementResult[
    InputRefinement] {.requires: outcome.status == WorkJobResultKind.RefinementFailure.} =
  ## Preserve the existing execution pipeline's actual failed child.
  outcome.refinementReason
func dutyError*(outcome: WorkJobResult): WorkDutyResult[WorkDuty] {.requires: outcome.status ==
    WorkJobResultKind.DutyFailure.} =
  ## Preserve actual source/assignment refusal before any authorizer executes or a grant escapes.
  outcome.dutyReason
proc duty*(context: AuthorizedWorkContext): WorkDuty =
  ## Copy detached assignment facts only while the caller owns graph access; old computation-only contexts have no duty claim.
  let data = context.data
  if data == nil: return default(WorkDuty)
  data.duty
func reportTranscript*(outcome: WorkJobResult): ComputedGuaranteeTranscript {.requires: outcome.status ==
    WorkJobResultKind.Reported.} =
  ## Only genuine complete report preparation exposes its original-bound transcript, never a signature or inclusion certificate.
  outcome.report
func reportPreparationError*(outcome: WorkJobResult): WorkReportResult {.requires: outcome.status ==
    WorkJobResultKind.ReportFailure.} =
  ## Preserve the exact selected report/bundle/availability stage failure without exposing earlier owners.
  outcome.reportReason
func valid*(job: WorkSubmissionJob): bool =
  ## Only private factories bind the actual runner and original source.
  job.data != nil
func valid*(context: AuthorizedWorkContext): bool =
  ## Default contexts never grant body CPU admission.
  context.data != nil
proc info*(context: AuthorizedWorkContext): WorkSubmissionResult[WorkSubmissionInfo] =
  ## Copy geometry while canonical graph access is available; the caller must retire this activation before another job starts.
  let data = context.data
  if data == nil: return default(WorkSubmissionResult[WorkSubmissionInfo])
  data.grant.submissionInfo
proc authorize(data: WorkJobData): WorkJobResult =
  ## Private staging aliases retire before the worker publishes Done.
  let source = data.source
  var duty = default(WorkDuty)
  if source.recipient.valid:
    # Network requests must prove the original local core assignment inside the same exclusive CPU lease.
    let selected = captureWorkDuty(source.state, source.parameters, source.recipient,
      source.header.submissionInfo.value.core, source.dutyLimits)
    if selected.error != WorkDutyError.None:
      return WorkJobResult(status: WorkJobResultKind.DutyFailure, dutyReason: selected)
    duty = selected.value
  let outcome = authorizeWorkSubmission(source.header, source.state, source.parameters, source.limits)
  if outcome.error != WorkSubmissionError.None:
    return WorkJobResult(status: WorkJobResultKind.AuthorizationFailure,
        authorizationReason: outcome)
  WorkJobResult(status: WorkJobResultKind.Authorized,
    context: AuthorizedWorkContext(data: WorkContextData(source: source, grant: outcome.value, duty: duty)))
proc complete(data: WorkJobData): WorkJobResult =
  ## Validate only the original grant's body, then execute from the same immutable source and fixed original policy.
  let context = data.context.data
  if context == nil: return default(WorkJobResult)
  let source = context.source
  let described = context.grant.submissionInfo.value
  let inputs = if described.kind == WorkSubmissionKind.Bundle:
    completeBundleSubmission(context.grant, data.extrinsics, data.segments, data.proofs, source.limits)
  else:
    completePackageSubmission(context.grant, data.extrinsics, data.imports, data.lookup, source.limits)
  if inputs.error != WorkSubmissionError.None:
    return WorkJobResult(status: WorkJobResultKind.BodyFailure, bodyReason: inputs)
  let executed = runInputRefinement(source.state, inputs.value, described.core, source.parameters,
      source.execution)
  if executed.error != InputRefinementError.None:
    return WorkJobResult(status: WorkJobResultKind.RefinementFailure, refinementReason: executed)
  WorkJobResult(status: WorkJobResultKind.Refined, execution: executed.value)
proc report(data: WorkJobData): WorkJobResult =
  ## Original refinement stays under the same graph lease through every bounded encoding/hash stage.
  let computed = prepareWorkReport(data.refined, data.shards, data.reportLimits)
  if computed.error != WorkReportError.None:
    return WorkJobResult(status: WorkJobResultKind.ReportFailure, reportReason: computed)
  WorkJobResult(status: WorkJobResultKind.Reported, report: computed.value)
proc captureWorkReport*(source: InputRefinement, shards: ErasureShards,
    limits: WorkReportLimits): WorkJobAdmission =
  ## Capture only a genuine refinement owner; staging aliases retire before the moved job enters the exclusive worker.
  if source.inputRefinementIdentity.error != InputRefinementError.None:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: report, refined: source, shards: shards, reportLimits: limits)))
proc captureWorkAuthorization*(header: WorkSubmissionHeader, state: StateStoreSnapshot,
    parameters: Parameters, limits: WorkSubmissionLimits,
    execution: InputRefinementLimits, recipient = default(WorkRecipient),
    dutyLimits = default(WorkDutyLimits)): WorkJobAdmission =
  ## The staging caller owns the shared graph; every returned alias must retire before it submits the moved job.
  if header.submissionInfo.error != WorkSubmissionError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if not parameters.valid: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not sameStateSnapshot(state, state): return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let source = WorkSource(header: header, state: state, parameters: parameters, limits: limits,
      execution: execution, recipient: recipient, dutyLimits: dutyLimits)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: authorize, source: source)))
proc copied(input: openArray[byte]): seq[byte] =
  ## Bounded callers receive independent bytes; later input mutation cannot change a pending job.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]
proc captureWorkBundle*(context: AuthorizedWorkContext, extrinsics, segments,
    proofs: openArray[byte]): WorkJobAdmission =
  ## Preflight complete message geometry before copying any body bytes under the shared graph gate.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let info = data.grant.submissionInfo.value
  if info.kind != WorkSubmissionKind.Bundle: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if extrinsics.len != info.extrinsicBytes or segments.len != info.segmentBytes:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if proofs.len > info.importCount*385: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  if info.packageBytes+extrinsics.len+segments.len+proofs.len > 13904950:
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: complete, source: data.source, context: context,
    extrinsics: copied(extrinsics), segments: copied(segments), proofs: copied(proofs))))
proc captureWorkPackage*(context: AuthorizedWorkContext, extrinsics: openArray[byte],
    imports: openArray[seq[VerifiedImport]], lookup: openArray[SegmentLookup]): WorkJobAdmission =
  ## CE133 receives separately verified availability witnesses; exact original binding still occurs on the CPU.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let info = data.grant.submissionInfo.value
  if info.kind != WorkSubmissionKind.Package or extrinsics.len != info.extrinsicBytes:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if imports.len > 16 or lookup.len > 8: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  var count = 0
  for row in imports:
    if row.len > 3072-count: return WorkJobAdmission(status: WorkJobError.LimitExceeded)
    count += row.len
  var rows = newSeq[seq[VerifiedImport]](imports.len)
  for item in 0..<imports.len:
    # Descriptor copies own independent rows; each verified leaf is itself immutable acyclic storage.
    rows[item] = newSeq[VerifiedImport](imports[item].len)
    for index in 0..<imports[item].len: rows[item][index] = imports[item][index]
  var dictionary = newSeq[SegmentLookup](lookup.len)
  for index in 0..<lookup.len: dictionary[index] = lookup[index]
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: complete, source: data.source, context: context,
    extrinsics: copied(extrinsics), imports: rows, lookup: dictionary)))
proc executeWorkSubmission*(job: WorkSubmissionJob): WorkJobResult =
  ## The worker invokes a private genuine capability outside native callbacks and retires all activation aliases before Done.
  let data = job.data
  if data == nil: return default(WorkJobResult)
  let run = data.run
  if run == nil: return default(WorkJobResult)
  run(data)
