# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct bundle evaluation grants a positive audit capability only after actual authorization, refinement, availability reconstruction and complete canonical report equality. Failed direct candidates grant no negative capability and may require authenticated CE138 recovery.
import ./[audit_origin, audit_context, work_report]
from ./assurance_store import AssuranceScanControl, stopped
import ./audit_recovery
import ../chain/[genesis, parameters, reports]
import ../codec/[bounded, owned, report_owned]
import ../codec/work/[package as work_package, report as work_report_codec, digest as work_digest]
import ../state/[audit_bundle, input_refinement]
from ../state/extrinsic_inputs import ExtrinsicInputsError
from "../state/import/justification" import ImportJustificationError
from "../state/import/inputs" import ImportInputsError
import ../state/computed/[report as computed_report, guarantee as computed_guarantee]

type
  AuditEvaluationLimits* = object ## Complete input/PVM/report policies and a separate comparison copy ceiling are explicit; private source parameters determine consensus package gas.
    bundle*: AuditBundleLimits
    execution*: InputRefinementLimits
    report*: WorkReportLimits
    comparisonBytes*: ByteLimit
  AuditEvaluationInfo* = object ## Copied result metadata cannot construct or replace the private completed execution capability.
    blockHash*: genesis.BlockHash
    reportHash*: WorkReportHash
    epoch*: uint64
    core*: CoreIndex
    positive*: bool
  EvaluationData = ref object ## Immutable provenance retains the actual registered report origin; all expensive temporary execution/encoding owners retire before publication.
    source: AuditReportOrigin
    info: AuditEvaluationInfo
  AuditEvaluation* = object ## No caller-supplied validity bit, report bytes or detached digest can construct this capability.
    data: nil EvaluationData
  AuditEvaluationError* {.pure.} = enum ## Failed direct candidates contain diagnostics only, never negative judgments or successful earlier execution prefixes.
    Uninitialized, None, InvalidPolicy, InvalidOrigin, InvalidRecovery, LimitExceeded, Cancelled,
    BundleFailure, ExecutionFailure, ReportFailure, EncodingFailure, Mismatch
  AuditEvaluationResult*[T] = object ## Every selected child is a genuine failed operation; only whole equality contains a completed capability.
    case status: AuditEvaluationError
    of None: completed: T
    of BundleFailure: bundleReason: AuditBundleResult[DecodedAuditBundle]
    of ExecutionFailure: executionReason: InputRefinementResult[InputRefinement]
    of ReportFailure: reportReason: WorkReportResult
    of EncodingFailure: encodingReason: OwnershipError
    else: discard # Defaults, cancellation, comparison/resource refusals expose no accepted prefix.
func error*[T](outcome: AuditEvaluationResult[T]): AuditEvaluationError =
  ## Inspect the selected result before extracting metadata or actual child failures.
  outcome.status
func value*[T](outcome: AuditEvaluationResult[T]): T {.requires: outcome.status ==
    AuditEvaluationError.None.} =
  ## Only a real complete computation/report equality grants a positive audit capability.
  outcome.completed
func bundleError*[T](outcome: AuditEvaluationResult[T]): AuditBundleResult[
    DecodedAuditBundle] {.requires: outcome.status == AuditEvaluationError.BundleFailure.} =
  ## Format/commitment failure remains distinct from local input policy or backend refusal.
  outcome.bundleReason
func executionError*[T](outcome: AuditEvaluationResult[T]): InputRefinementResult[
    InputRefinement] {.requires: outcome.status == AuditEvaluationError.ExecutionFailure.} =
  ## Preserve genuine authorizer/refiner diagnostics without retaining a successful execution prefix.
  outcome.executionReason
func reportError*[T](outcome: AuditEvaluationResult[
    T]): WorkReportResult {.requires: outcome.status == AuditEvaluationError.ReportFailure.} =
  ## Whole original availability/report reconstruction retains its actual failed stage only.
  outcome.reportReason
func encodingError*[T](outcome: AuditEvaluationResult[
    T]): OwnershipError {.requires: outcome.status == AuditEvaluationError.EncodingFailure.} =
  ## Failure to serialize the original retained canonical report grants no comparison success.
  outcome.encodingReason
func valid*(limits: AuditEvaluationLimits): bool =
  ## Cover every possible package prefix within the permitted whole wire so a parser limit is distinguishable from a local prefix-byte refusal; all new copies stay finite.
  limits.bundle.valid and uint64(limits.bundle.package.maxBytes) >= uint64(limits.bundle.bytes) and
    uint64(limits.comparisonBytes) > 0 and uint64(limits.comparisonBytes) <= 256'u64*1024 and
    uint64(limits.execution.inputBytes) > 0 and uint64(limits.execution.inputBytes) <=
        64'u64*1024*1024 and
    uint64(limits.report.bundleBytes) > 0 and uint64(limits.report.bundleBytes) <= uint64(
        MaxBundleBytes) and
    uint64(limits.report.layoutBytes) > 0 and uint64(limits.report.layoutBytes) <=
        64'u64*1024*1024 and
    uint64(limits.report.reportBytes) > 0 and uint64(limits.report.reportBytes) <= 1024'u64*1024 and
    uint64(limits.report.transcriptBytes) > 0 and uint64(limits.report.transcriptBytes) <=
        2'u64*1024*1024
func valid*(evaluation: AuditEvaluation): bool =
  ## A default has no source, signed report identity or completed reproduction.
  evaluation.data != nil
func matchesOrigin*(evaluation: AuditEvaluation, origin: AuditReportOrigin): bool =
  ## Services can require exact registered private source ownership before lending a signing key; copied public hashes/booleans cannot substitute.
  let data = evaluation.data
  data != nil and sameAuditOrigin(data.source, origin)
proc evaluationInfo*(evaluation: AuditEvaluation): AuditEvaluationResult[AuditEvaluationInfo] =
  ## Copy fixed facts only after exact worker collection; source-bearing aliases remain frozen while another job borrows them.
  let data = evaluation.data
  if data == nil: return AuditEvaluationResult[AuditEvaluationInfo](
      status: AuditEvaluationError.Uninitialized)
  AuditEvaluationResult[AuditEvaluationInfo](status: AuditEvaluationError.None,
      completed: data.info)
proc evaluationOrigin*(evaluation: AuditEvaluation): AuditEvaluationResult[AuditReportOrigin] =
  ## Only the leased signer/evaluator may follow original source provenance; no writable or replacement full-state view is exported.
  let data = evaluation.data
  if data == nil: return AuditEvaluationResult[AuditReportOrigin](
      status: AuditEvaluationError.Uninitialized)
  AuditEvaluationResult[AuditReportOrigin](status: AuditEvaluationError.None,
      completed: data.source)
func needsRecovery*(outcome: AuditEvaluationResult[AuditEvaluation]): bool =
  ## Invalid unproved direct bytes can trigger authenticated reconstruction, never a negative judgment. Local policy, missing code/history and backend failures remain unavailable evaluation.
  case outcome.status
  of AuditEvaluationError.Mismatch: true
  of AuditEvaluationError.BundleFailure:
    let failed = outcome.bundleReason
    case failed.error
    of AuditBundleError.LengthMismatch, AuditBundleError.Truncated, AuditBundleError.TrailingBytes,
        AuditBundleError.InvalidProof, AuditBundleError.InvalidLookup,
            AuditBundleError.PackageHashMismatch: true
    of AuditBundleError.PackageFailure:
      failed.packageError in [PackageError.Truncated, PackageError.NonCanonical,
          PackageError.LimitExceeded]
    of AuditBundleError.ExtrinsicFailure:
      failed.extrinsicError in [ExtrinsicInputsError.InvalidShape,
          ExtrinsicInputsError.LengthMismatch, ExtrinsicInputsError.HashMismatch]
    of AuditBundleError.ImportFailure:
      failed.importError in [ImportJustificationError.InvalidProof,
          ImportJustificationError.InvalidIndex, ImportJustificationError.RootMismatch]
    of AuditBundleError.BindingFailure:
      failed.bindingError in [ImportInputsError.InvalidShape, ImportInputsError.InvalidLookup,
        ImportInputsError.NonCanonical,
        ImportInputsError.InvalidImport, ImportInputsError.IndexMismatch,
        ImportInputsError.RootMismatch]
    else: false # Uninitialized/local byte-workspace/hash/backend failures do not prove anything about the report.
  of AuditEvaluationError.ExecutionFailure:
    outcome.executionReason.error in [InputRefinementError.AuthorizationRejected,
        InputRefinementError.TraceTooLarge]
  of AuditEvaluationError.ReportFailure:
    outcome.reportReason.error == WorkReportError.ReportFailure and
        outcome.reportReason.reportError == ComputedReportError.InvalidReport
  else: false # Default, cancellation, impossible source and local computation/copy refusals produce no negative evidence or spurious network retry.
proc completedEvaluation(origin: AuditReportOrigin, positive: bool): AuditEvaluationResult[
    AuditEvaluation] =
  ## Private construction follows actual equality or exact authenticated reconstruction evidence, never a caller-selected validity flag.
  let source = origin.originInfo.value
  let context = origin.originContext.value.contextInfo.value
  let report = origin.originReport.value.ownedReportInfo.value
  AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.None,
    completed: AuditEvaluation(data: EvaluationData(source: origin,
      info: AuditEvaluationInfo(blockHash: source.blockHash,
        reportHash: origin.originReportHash.value, epoch: context.epoch,
        core: report.core, positive: positive))))
proc evaluateDirectAudit*(origin: AuditReportOrigin, wire: openArray[byte],
    limits: AuditEvaluationLimits, control: AssuranceScanControl = default(
        AssuranceScanControl)): AuditEvaluationResult[AuditEvaluation] =
  ## Run on the actual managed worker with every source alias frozen. Only full canonical equality certifies positive judgment; this entry point cannot create a negative capability.
  if not limits.valid: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.InvalidPolicy)
  if not origin.valid: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.InvalidOrigin)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  if uint64(wire.len) > uint64(limits.report.bundleBytes):
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.LimitExceeded)
  let original = origin.originReport.value
  let described = original.ownedReportInfo.value
  if uint64(described.consumed) > uint64(limits.comparisonBytes):
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.LimitExceeded)
  let parameters = origin.originParameters.value
  let state = origin.originState.value
  var lookup = newSeq[SegmentLookup](described.lookupCount)
  for ordinal in 0..<lookup.len:
    lookup[ordinal] = original.ownedReportLookup(ordinal).value # Exact signed report dictionary, never an independently supplied root table.
  var decoding = limits.bundle
  decoding.package.refineGas = Gas(parameters.get(maxRefineGas))
  decoding.package.accumulateGas = Gas(parameters.get(maxAccumulateGas))
  let decoded = decodeAuditBundle(wire, described.header, lookup, decoding)
  if decoded.error != AuditBundleError.None:
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.BundleFailure,
        bundleReason: decoded)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  let executed = runInputRefinement(state, decoded.value.decodedInputs.value, described.core,
    parameters, limits.execution)
  if executed.error != InputRefinementError.None:
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.ExecutionFailure,
        executionReason: executed)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  let computed = prepareWorkReport(executed.value, described.header.erasureShards, limits.report)
  if computed.error != WorkReportError.None:
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.ReportFailure,
        reportReason: computed)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  let report = computed.value.computedGuaranteeReport.value
  let info = report.computedReportInfo.value
  if uint64(described.consumed) > uint64(limits.comparisonBytes) or
      info.length > uint64(limits.comparisonBytes)-uint64(described.consumed):
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.LimitExceeded)
  var expected = newSeq[byte](described.consumed)
  let encoded = original.encodeOwnedReport(expected)
  if encoded.error != OwnershipError.None:
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.EncodingFailure,
        encodingReason: encoded.error)
  if expected != report.computedReportBytes.value:
    return AuditEvaluationResult[AuditEvaluation](status: AuditEvaluationError.Mismatch)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  completedEvaluation(origin, true)

proc evaluateRecoveredAudit*(origin: AuditReportOrigin, evidence: AuditRecoveryEvidence,
    limits: AuditEvaluationLimits, control: AssuranceScanControl = default(
        AssuranceScanControl)): AuditEvaluationResult[AuditEvaluation] =
  ## Only actual original-root recovery can turn a protocol-invalid bundle/computation into a negative capability. Resource, history, backend and cancellation refusals remain unavailable.
  if not limits.valid: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.InvalidPolicy)
  if not origin.valid: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.InvalidOrigin)
  if not evidence.matchesOrigin(origin): return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.InvalidRecovery)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  if evidence.invalidPadding: return completedEvaluation(origin, false)
  let wire = evidence.recoveredBundle
  if wire.error != AuditRecoveryError.None: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.InvalidRecovery)
  let evaluated = evaluateDirectAudit(origin, wire.value, limits, control)
  if control.stopped: return AuditEvaluationResult[AuditEvaluation](
      status: AuditEvaluationError.Cancelled)
  if evaluated.needsRecovery: return completedEvaluation(origin, false)
  evaluated
