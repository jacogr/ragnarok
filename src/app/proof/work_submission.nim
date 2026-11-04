# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed two-stage work-submission CPU jobs retain original complete-state provenance under the shared graph lease.
## All aliases, including completed authorization and refinement, remain untouched until exact collection or joined stop.
import ../../jamnp-s/work_submission
import ../../jamnp-s/work_duty
import ../../jamnp-s/work_report
import ../../jamnp-s/work_recovery
import ../../chain/[provider, genesis]
from ../../codec/state/safrole import StateValidatorIndex
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
      DutyFailure, Reported, ReportFailure, ImportPlanningFailure, RecoveryUpdated, RecoveryFailure, RecoveryCompletionFailure
  WorkSource = ref object ## Immutable acyclic provenance retains the exact original complete map, package header and policy.
    header: WorkSubmissionHeader
    state: StateStoreSnapshot
    parameters: Parameters
    limits: WorkSubmissionLimits
    execution: InputRefinementLimits
    recipient: WorkRecipient
    dutyLimits: WorkDutyLimits
    view: ChainView
    recovery: WorkRecoveryPolicy
  WorkContextData = ref object ## A real successful grant cannot be rebound to another source or execution policy.
    source: WorkSource
    grant: AuthorizedWorkSubmission
    duty: WorkDuty
    imports: WorkImportPlan
    recovery: WorkRecovery
  AuthorizedWorkContext* = object ## Only a successful private CPU capability can construct a usable context.
    data: nil WorkContextData
  WorkJobResult* = object ## Failed/default results expose no input, grant, partial refinement or unrelated child.
    case status: WorkJobResultKind
    of RecoveryUpdated: recovered: WorkRecovery
    of RecoveryFailure: recoveryReason: WorkRecoveryResult[WorkRecovery]
    of RecoveryCompletionFailure: recoveryCompletionReason: WorkRecoveryResult[VerifiedImportInputs]
    of ImportPlanningFailure: planningReason: WorkSubmissionResult[WorkImportPlan]
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
    recovery: WorkRecovery
    recoveryVersion: uint64
    validator: StateValidatorIndex
    fetched: bool
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
proc importRequest*(context: AuthorizedWorkContext): WorkSubmissionResult[seq[byte]] =
  ## Detach request bytes only while the shared graph is idle; no context or grant alias leaves in the returned buffer.
  let data = context.data
  if data == nil: return default(WorkSubmissionResult[seq[byte]])
  data.imports.workImportRequest
func importPlanningError*(outcome: WorkJobResult): WorkSubmissionResult[WorkImportPlan] {.requires:
    outcome.status == WorkJobResultKind.ImportPlanningFailure.} =
  ## Preserve a genuine missing/conflicting source mapping refusal without exposing a usable partial plan.
  outcome.planningReason
proc recovery*(context: AuthorizedWorkContext): WorkRecovery =
  ## Retain the initial private progress only while graph access is idle; hosts use detached Services metadata instead.
  let data = context.data
  if data == nil: return default(WorkRecovery)
  data.recovery
func recovery*(outcome: WorkJobResult): WorkRecovery {.requires: outcome.status ==
    WorkJobResultKind.RecoveryUpdated.} =
  ## Only a genuine completed CPU step exposes its next immutable private progress.
  outcome.recovered
func recoveryError*(outcome: WorkJobResult): WorkRecoveryResult[
    WorkRecovery] {.requires: outcome.status == WorkJobResultKind.RecoveryFailure.} =
  ## Preserve the exact packet/catalog refusal with no successful prefix.
  outcome.recoveryReason
func recoveryCompletionError*(outcome: WorkJobResult): WorkRecoveryResult[
    VerifiedImportInputs] {.requires: outcome.status ==
    WorkJobResultKind.RecoveryCompletionFailure.} =
  ## Preserve complete original-package binding refusal.
  outcome.recoveryCompletionReason
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
  var imports = default(WorkImportPlan)
  if source.header.submissionInfo.value.kind == WorkSubmissionKind.Package:
    # Package-only imports are planned on the same CPU turn and exact state as successful authorization.
    let planned = prepareWorkImportPlan(outcome.value, source.limits)
    if planned.error != WorkSubmissionError.None:
      return WorkJobResult(status: WorkJobResultKind.ImportPlanningFailure, planningReason: planned)
    imports = planned.value
  var recovered = default(WorkRecovery)
  if source.recovery.valid and source.header.submissionInfo.value.kind ==
      WorkSubmissionKind.Package:
    # Catalog capture and original-map binding share this exact authorization lease; no host-provided report descriptor enters.
    let planned = beginWorkRecovery(imports, source.view, source.recovery)
    if planned.error != WorkRecoveryError.None:
      return WorkJobResult(status: WorkJobResultKind.RecoveryFailure, recoveryReason: planned)
    recovered = planned.value
  # Catalog rows retain only their original descriptors/rosters; network waits must not pin every old complete state in the captured view.
  let retained = WorkSource(header: source.header, state: source.state,
    parameters: source.parameters,
    limits: source.limits, execution: source.execution, recipient: source.recipient,
    dutyLimits: source.dutyLimits,
    view: default(ChainView), recovery: source.recovery)
  WorkJobResult(status: WorkJobResultKind.Authorized,
    context: AuthorizedWorkContext(data: WorkContextData(source: retained, grant: outcome.value,
        duty: duty, imports: imports, recovery: recovered)))
proc refine(context: WorkContextData, inputs: VerifiedImportInputs): WorkJobResult =
  ## Every path executes the same original source, core and immutable refinement policy after complete input binding.
  let source = context.source
  let described = context.grant.submissionInfo.value
  let executed = runInputRefinement(source.state, inputs, described.core, source.parameters,
      source.execution)
  if executed.error != InputRefinementError.None:
    return WorkJobResult(status: WorkJobResultKind.RefinementFailure, refinementReason: executed)
  WorkJobResult(status: WorkJobResultKind.Refined, execution: executed.value)
proc recoverPacket(data: WorkJobData): WorkJobResult =
  ## No native or host alias is touched while both proof pieces and any threshold reconstruction run on this lease.
  let completed = acceptRecoveryPacket(data.recovery, data.recoveryVersion, data.validator, data.segments)
  if completed.error != WorkRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.RecoveryFailure, recoveryReason: completed)
  WorkJobResult(status: WorkJobResultKind.RecoveryUpdated, recovered: completed.value)
proc retryRecovery(data: WorkJobData): WorkJobResult =
  ## Discard unproven packet ownership only on the private managed CPU lease, never from a callback or busy host.
  let completed = retryRecoveryProven(data.recovery)
  if completed.error != WorkRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.RecoveryFailure, recoveryReason: completed)
  WorkJobResult(status: WorkJobResultKind.RecoveryUpdated, recovered: completed.value)
proc completeRecovered(data: WorkJobData): WorkJobResult =
  ## The exact original grant owns both recovery and complete binding before real source-bound execution.
  let context = data.context.data
  if context == nil: return default(WorkJobResult)
  let completed = completeRecoveredWork(data.recovery, context.grant, data.extrinsics,
      context.source.limits)
  if completed.error != WorkRecoveryError.None:
    return WorkJobResult(status: WorkJobResultKind.RecoveryCompletionFailure,
        recoveryCompletionReason: completed)
  refine(context, completed.value)
proc complete(data: WorkJobData): WorkJobResult =
  ## Validate only the original grant's body, then execute from the same immutable source and fixed original policy.
  let context = data.context.data
  if context == nil: return default(WorkJobResult)
  let source = context.source
  let described = context.grant.submissionInfo.value
  let inputs = if described.kind == WorkSubmissionKind.Bundle:
    completeBundleSubmission(context.grant, data.extrinsics, data.segments, data.proofs, source.limits)
  elif data.fetched:
    completeFetchedPackageSubmission(context.grant, context.imports, data.extrinsics, data.segments, source.limits)
  else:
    completePackageSubmission(context.grant, data.extrinsics, data.imports, data.lookup, source.limits)
  if inputs.error != WorkSubmissionError.None:
    return WorkJobResult(status: WorkJobResultKind.BodyFailure, bodyReason: inputs)
  refine(context, inputs.value)
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
    execution: InputRefinementLimits, recipient: WorkRecipient,
    dutyLimits: WorkDutyLimits, view: ChainView,
    recovery: WorkRecoveryPolicy): WorkJobAdmission =
  ## The staging caller owns the shared graph; every returned alias must retire before it submits the moved job.
  if header.submissionInfo.error != WorkSubmissionError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if not parameters.valid: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not sameStateSnapshot(state, state): return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if recovery.valid and header.submissionInfo.value.kind == WorkSubmissionKind.Package:
    # Bound the captured view container and reject a distinct posterior owner before retaining any source aliases for the worker.
    if uint64(view.retainedCount) > uint64(recovery.limits.catalog.blocks):
      return WorkJobAdmission(status: WorkJobError.LimitExceeded)
    let head = view.bestBlock
    if head.error != GenesisError.None: return WorkJobAdmission(status: WorkJobError.InvalidInput)
    if not sameStateSnapshot(head.value.stateSnapshot, state): return WorkJobAdmission(
        status: WorkJobError.InvalidInput)
  let source = WorkSource(header: header, state: state, parameters: parameters, limits: limits,
      execution: execution, recipient: recipient, dutyLimits: dutyLimits, view: view,
      recovery: recovery)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: authorize, source: source)))
proc captureWorkAuthorization*(header: WorkSubmissionHeader, state: StateStoreSnapshot,
    parameters: Parameters, limits: WorkSubmissionLimits, execution: InputRefinementLimits,
    recipient = default(WorkRecipient), dutyLimits = default(WorkDutyLimits)): WorkJobAdmission =
  ## Computation-only callers need no chain context; keep the complex private variant default inside its owning factory.
  ## The pinned compiler rejects direct variant defaults in omitted arguments; see NIM-006.
  captureWorkAuthorization(header, state, parameters, limits, execution, recipient, dutyLimits,
    genesisView(unavailableGenesis()), default(WorkRecoveryPolicy))
proc copied(input: openArray[byte]): seq[byte] =
  ## Bounded callers receive independent bytes; later input mutation cannot change a pending job.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]
proc captureWorkRecoveryPacket*(context: AuthorizedWorkContext, recovery: WorkRecovery,
    version: uint64, validator: StateValidatorIndex, wire: openArray[byte]): WorkJobAdmission =
  ## Deep-copy only bounded raw bytes; caller progress/context aliases retire before the submitted closed CPU job executes.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not recovery.recoveryMatches(data.grant): return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  let request = recovery.recoveryRequest(validator)
  if request.error != WorkRecoveryError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if request.value.version != version: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if uint64(wire.len) > uint64(request.value.maximum): return WorkJobAdmission(
      status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: recoverPacket, context: context, recovery: recovery, recoveryVersion: version,
    validator: validator, segments: copied(wire))))
proc captureWorkRecoveryRetry*(context: AuthorizedWorkContext,
    recovery: WorkRecovery): WorkJobAdmission =
  ## Only matching private progress can change trust mode; no raw peer response or caller flag fabricates proven packets.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not recovery.recoveryMatches(data.grant): return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  let info = recovery.recoveryInfo
  if info.error != WorkRecoveryError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if info.value.complete or info.value.proven: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: retryRecovery, context: context, recovery: recovery)))
proc captureRecoveredWorkPackage*(context: AuthorizedWorkContext, recovery: WorkRecovery,
    extrinsics: openArray[byte]): WorkJobAdmission =
  ## Only complete matching private progress can enter the original full input/refinement pipeline.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if not recovery.recoveryMatches(data.grant): return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  let info = recovery.recoveryInfo
  if info.error != WorkRecoveryError.None: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  if not info.value.complete: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if extrinsics.len != data.grant.submissionInfo.value.extrinsicBytes: return WorkJobAdmission(
      status: WorkJobError.InvalidInput)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: completeRecovered, context: context, recovery: recovery, extrinsics: copied(extrinsics))))
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
proc captureFetchedWorkPackage*(context: AuthorizedWorkContext, extrinsics,
    reply: openArray[byte]): WorkJobAdmission =
  ## Copy only bounded untrusted bytes; original plan verification and refinement run together on the exclusive CPU worker.
  let data = context.data
  if data == nil: return WorkJobAdmission(status: WorkJobError.InvalidInput)
  let info = data.grant.submissionInfo.value
  if info.kind != WorkSubmissionKind.Package or extrinsics.len != info.extrinsicBytes:
    return WorkJobAdmission(status: WorkJobError.InvalidInput)
  if reply.len > 8+info.segmentBytes+info.importCount*385:
    return WorkJobAdmission(status: WorkJobError.LimitExceeded)
  WorkJobAdmission(status: WorkJobError.None, completed: WorkSubmissionJob(data: WorkJobData(
    run: complete, source: data.source, context: context, fetched: true,
    extrinsics: copied(extrinsics), segments: copied(reply))))
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
