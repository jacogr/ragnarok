# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive report and guarantee transcript only through genuine original refinement, bundle and availability provenance.
import ../codec/bounded
from ../codec/work/report import ErasureShards
import ../state/[input_refinement, auditable_bundle, bundle_erasure]
import ../state/erasure/layout
import "../state/export/erasure" as export_erasure
import ../state/availability/specifier
import ../state/computed/[report, guarantee]

type
  WorkReportLimits* = object ## Independent stage ceilings are explicit local policy; none changes protocol encoding or grants signing authority.
    bundleBytes*, layoutBytes*, reportBytes*, transcriptBytes*: ByteLimit
    bundle*: BundleErasureLimits
    exports*: ExportErasureLimits
    availability*: AvailabilityCommitmentLimits
  WorkReportError* {.pure.} = enum ## Defaults and failures contain no completed report, transcript or partial artifact.
    Uninitialized, None, BundleFailure, LayoutFailure, BundleEncodingFailure,
      ExportEncodingFailure, AvailabilityFailure, ReportFailure, TranscriptFailure
  WorkReportResult* = object ## Private selected children preserve only genuine component failures or complete original-bound success.
    case status: WorkReportError
    of None: completed: ComputedGuaranteeTranscript
    of BundleFailure: bundleReason: AuditableBundleError
    of LayoutFailure: layoutReason: ErasureLayoutError
    of BundleEncodingFailure: bundleEncodingReason: BundleErasureError
    of ExportEncodingFailure: exportEncodingReason: ExportErasureError
    of AvailabilityFailure: availabilityReason: AvailabilityCommitmentError
    of ReportFailure: reportReason: ComputedReportError
    of TranscriptFailure: transcriptReason: ComputedGuaranteeError
    else: discard # An uninitialized result has neither a source nor an invented failure child.
func error*(outcome: WorkReportResult): WorkReportError =
  ## Scalar failure inspection does not expose successful owners.
  outcome.status
func value*(outcome: WorkReportResult): ComputedGuaranteeTranscript {.requires: outcome.status ==
    WorkReportError.None.} =
  ## A transcript retains its own computed report, which retains the entire original execution/availability chain.
  outcome.completed
func bundleError*(outcome: WorkReportResult): AuditableBundleError {.requires: outcome.status ==
    WorkReportError.BundleFailure.} =
  ## Preserve only the actual failed original bundle encoder.
  outcome.bundleReason
func layoutError*(outcome: WorkReportResult): ErasureLayoutError {.requires: outcome.status ==
    WorkReportError.LayoutFailure.} =
  ## Invalid shard geometry and local layout budgets retain their genuine distinction.
  outcome.layoutReason
func bundleEncodingError*(outcome: WorkReportResult): BundleErasureError {.requires: outcome.status ==
    WorkReportError.BundleEncodingFailure.} =
  ## Parity encoding failure carries no systematic/parity prefix.
  outcome.bundleEncodingReason
func exportEncodingError*(outcome: WorkReportResult): ExportErasureError {.requires: outcome.status ==
    WorkReportError.ExportEncodingFailure.} =
  ## Preserve the selected export/tree/coding error without inventing a nested unavailable cause.
  outcome.exportEncodingReason
func availabilityError*(outcome: WorkReportResult): AvailabilityCommitmentError {.requires: outcome.status ==
    WorkReportError.AvailabilityFailure.} =
  ## No accepted validator-leaf prefix escapes availability refusal.
  outcome.availabilityReason
func reportError*(outcome: WorkReportResult): ComputedReportError {.requires: outcome.status ==
    WorkReportError.ReportFailure.} =
  ## Canonical report serialization errors do not expose earlier availability ownership.
  outcome.reportReason
func transcriptError*(outcome: WorkReportResult): ComputedGuaranteeError {.requires: outcome.status ==
    WorkReportError.TranscriptFailure.} =
  ## Preserve actual hashing/resource failures without a signature or partial message.
  outcome.transcriptReason
proc prepareWorkReport*(source: InputRefinement, shards: ErasureShards,
    limits: WorkReportLimits): WorkReportResult =
  ## Call under the managed graph lease; every intermediate owner retires before complete success or selected failure escapes.
  let bundled = prepareAuditableBundle(source, limits.bundleBytes)
  if bundled.error != AuditableBundleError.None:
    return WorkReportResult(status: WorkReportError.BundleFailure, bundleReason: bundled.error)
  let laid = prepareErasureLayout(bundled.value, shards, limits.layoutBytes)
  if laid.error != ErasureLayoutError.None:
    return WorkReportResult(status: WorkReportError.LayoutFailure, layoutReason: laid.error)
  let encoded = prepareBundleErasure(laid.value, limits.bundle)
  if encoded.error != BundleErasureError.None:
    return WorkReportResult(status: WorkReportError.BundleEncodingFailure,
        bundleEncodingReason: encoded.error)
  let exported = prepareExportErasure(encoded.value, limits.exports)
  if exported.error != ExportErasureError.None:
    return WorkReportResult(status: WorkReportError.ExportEncodingFailure,
        exportEncodingReason: exported.error)
  let committed = prepareAvailabilityCommitment(exported.value, limits.availability)
  if committed.error != AvailabilityCommitmentError.None:
    return WorkReportResult(status: WorkReportError.AvailabilityFailure,
        availabilityReason: committed.error)
  let assembled = prepareComputedReport(committed.value, limits.reportBytes)
  if assembled.error != ComputedReportError.None:
    return WorkReportResult(status: WorkReportError.ReportFailure, reportReason: assembled.error)
  let transcript = prepareComputedGuarantee(assembled.value, limits.transcriptBytes)
  if transcript.error != ComputedGuaranteeError.None:
    return WorkReportResult(status: WorkReportError.TranscriptFailure,
        transcriptReason: transcript.error)
  WorkReportResult(status: WorkReportError.None, completed: transcript.value)
