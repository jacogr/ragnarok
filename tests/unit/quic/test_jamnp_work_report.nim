# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_work_report_arc_release"}

## Genuine original report pipeline preserves bundle bytes, population-dependent commitments and exact failed stages.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[work_report, work_submission]
import ../../../src/codec/bounded
import ../../../src/chain/parameters
import ../../../src/codec/work/report
import ../../../src/state/[input_refinement, auditable_bundle, bundle_erasure, store]
import ../../../src/state/erasure/[layout, words]
import "../../../src/state/export/erasure" as export_erasure
import ../../../src/state/availability/specifier
import ../../../src/state/computed/[report as computed_report, guarantee]
import ../../../src/crypto/[primitives, guarantee as crypto_guarantee]
import ../../support/[jamnp_work_fixture, jamnp_work_report_fixture, pvm_input_refinement,
  pvm_export_erasure, arc_evidence]
proc original(transcript: ComputedGuaranteeTranscript): AuditableBundle =
  ## Traverse only the original immutable provenance; no detached replacement bytes are accepted by production factories.
  let computed = transcript.computedGuaranteeReport.value
  let availability = computed.computedReportSource.value
  let exports = availability.availabilitySource.value
  let bundle = exports.exportErasureSource.value
  bundle.bundleErasureSource.value.layoutSource.value
proc releaseCycle(source: InputRefinement) =
  ## Every newly encoded report, transcript and intermediate private owner retires before the next checked ARC cycle.
  let completed = prepareWorkReport(source, ErasureShards(6), workReportLimits())
  assert completed.error == WorkReportError.None, "report preparation: " & $completed.error
  assert completed.value.computedGuaranteeReport.value.computedReportInfo.value.items == 1
proc main() =
  ## Complete PVM/import execution precedes all new report work; failed results never act as a source.
  let fixture = workFixture()
  # Actual header authorization and body authentication preserve the original package into execution and report composition.
  let header = fixture.workHeader
  let grant = authorizeWorkSubmission(header, fixture.input.state, fixture.input.parameters,
    fixture.limits)
  assert grant.error == WorkSubmissionError.None
  let inputs = completeBundleSubmission(grant.value, fixture.extrinsics, fixture.segments,
    fixture.proofs, fixture.limits)
  assert inputs.error == WorkSubmissionError.None
  let bound = runInputRefinement(fixture.input.state, inputs.value, CoreIndex(0),
    fixture.input.parameters, executionLimits())
  assert bound.error == InputRefinementError.None
  let boundReport = prepareWorkReport(bound.value, ErasureShards(6), workReportLimits())
  assert boundReport.error == WorkReportError.None
  assert boundReport.value.workReportMatches(header, fixture.input.state, fixture.input.parameters)
  assert not boundReport.value.workReportMatches(fixture.workHeader, fixture.input.state,
      fixture.input.parameters)
  var fork = forkStateStore(fixture.input.state).value
  let key = fixture.input.state.keyAt(StateEntryIndex(0)).value
  let replacement = fork.apply([StateWrite(kind: StateWriteKind.Put, key: key,
    value: fixture.input.state.lookup(key).value.bytes)]).value
  assert array[32, byte](replacement.commitment.root) == array[32, byte](
      fixture.input.state.commitment.root)
  assert not sameStateSnapshot(replacement, fixture.input.state)
  assert not boundReport.value.workReportMatches(header, replacement, fixture.input.parameters)
  assert not default(ComputedGuaranteeTranscript).workReportMatches(header, fixture.input.state,
      fixture.input.parameters)
  assert not boundReport.value.workReportMatches(default(WorkSubmissionHeader), fixture.input.state,
      fixture.input.parameters)
  let changedProfile = fixture.input.parameters.withExplicitExpungePeriod.value
  assert not boundReport.value.workReportMatches(header, fixture.input.state, changedProfile)
  let refined = executionRun(fixture.input, core = 0)
  assert refined.error == InputRefinementError.None, "original refinement: " & $refined.error
  let completed = prepareWorkReport(refined.value, ErasureShards(6), workReportLimits())
  assert completed.error == WorkReportError.None, "report preparation: " & $completed.error
  assert not completed.value.workReportMatches(header,
      fixture.input.state, fixture.input.parameters) # Independent equal-byte package execution is not the admitted source.
  let transcript = completed.value
  let computed = transcript.computedGuaranteeReport.value
  let info = computed.computedReportInfo.value
  assert uint16(info.header.erasureShards) == 6 and uint64(info.core) == 0 and info.items == 2
  var expected = fixture.package
  for octet in fixture.extrinsics: expected.add(octet)
  for octet in fixture.segments: expected.add(octet)
  for octet in fixture.proofs: expected.add(octet)
  assert transcript.original.bundleBytes.value == expected, "original wire bundle is never replaced during availability preparation"
  let message = array[45, byte](transcript.computedGuaranteeMessage.value)
  let wire = computed.computedReportBytes.value
  let hash = blake2b256(wire)
  assert hash.error == CryptoError.None
  let domain = "jam_guarantee"
  for index in 0..<domain.len: assert message[index] == byte(domain[index])
  for index in 0..<32: assert message[domain.len+index] == array[32, byte](hash.value)[index]
  let narrow = prepareWorkReport(refined.value, ErasureShards(9), workReportLimits())
  assert narrow.error == WorkReportError.ReportFailure
  assert narrow.reportError == ComputedReportError.InvalidReport # A two-core source cannot publish nine validator shards.
  var expanded = fixture.input
  var parameters = expanded.parameters.encodeParameters
  parameters[24] = 3 # Configure three cores before creating a distinct genuine refinement, never rebind a completed owner.
  parameters[25] = 0
  expanded.parameters = decodeParameters(parameters).value
  let expandedRefined = executionRun(expanded, core = 0)
  assert expandedRefined.error == InputRefinementError.None
  let alternate = prepareWorkReport(expandedRefined.value, ErasureShards(9), workReportLimits())
  assert alternate.error == WorkReportError.None, "nine-shard report: " & $alternate.error
  let changed = alternate.value.computedGuaranteeReport.value.computedReportInfo.value
  assert uint16(changed.header.erasureShards) == 9
  assert changed.header.packageHash.bytes == info.header.packageHash.bytes
  assert changed.header.erasureRoot.bytes != info.header.erasureRoot.bytes, "population changes encoding commitment"
  let absent = prepareWorkReport(default(InputRefinement), ErasureShards(6), workReportLimits())
  assert absent.error == WorkReportError.BundleFailure
  assert absent.bundleError == AuditableBundleError.InvalidSource
  let invalid = prepareWorkReport(refined.value, ErasureShards(5), workReportLimits())
  assert invalid.error == WorkReportError.LayoutFailure and invalid.layoutError ==
      ErasureLayoutError.InvalidShards, "invalid shard geometry refusal"
  var limits = workReportLimits()
  limits.bundleBytes = ByteLimit(0)
  let bundleFailure = prepareWorkReport(refined.value, ErasureShards(6), limits)
  assert bundleFailure.error == WorkReportError.BundleFailure and bundleFailure.bundleError ==
      AuditableBundleError.LimitExceeded, "bundle refusal"
  limits = workReportLimits()
  limits.layoutBytes = ByteLimit(0)
  let layoutFailure = prepareWorkReport(refined.value, ErasureShards(6), limits)
  assert layoutFailure.error == WorkReportError.LayoutFailure and layoutFailure.layoutError ==
      ErasureLayoutError.LimitExceeded, "layout refusal"
  limits = workReportLimits()
  limits.bundle.products = FieldProductLimit(0)
  let codingFailure = prepareWorkReport(refined.value, ErasureShards(6), limits)
  assert codingFailure.error == WorkReportError.BundleEncodingFailure and
      codingFailure.bundleEncodingError == BundleErasureError.LimitExceeded, "bundle encoding refusal"
  let exporting = exportBundle(1, 6).bundleErasureSource.value.layoutSource.value.bundleSource.value
  limits = workReportLimits()
  limits.exports.bytes = ByteLimit(0)
  let exportFailure = prepareWorkReport(exporting, ErasureShards(6), limits)
  assert exportFailure.error == WorkReportError.ExportEncodingFailure and
      exportFailure.exportEncodingError == ExportErasureError.LimitExceeded, "export encoding refusal"
  limits = workReportLimits()
  limits.availability.bytes = ByteLimit(0)
  let availabilityFailure = prepareWorkReport(refined.value, ErasureShards(6), limits)
  assert availabilityFailure.error == WorkReportError.AvailabilityFailure and
      availabilityFailure.availabilityError == AvailabilityCommitmentError.LimitExceeded, "availability refusal"
  limits = workReportLimits()
  limits.reportBytes = ByteLimit(0)
  let reportFailure = prepareWorkReport(refined.value, ErasureShards(6), limits)
  assert reportFailure.error == WorkReportError.ReportFailure and reportFailure.reportError ==
      ComputedReportError.LimitExceeded, "report serialization refusal"
  limits = workReportLimits()
  limits.transcriptBytes = ByteLimit(0)
  let transcriptFailure = prepareWorkReport(refined.value, ErasureShards(6), limits)
  assert transcriptFailure.error == WorkReportError.TranscriptFailure and
      transcriptFailure.transcriptError == ComputedGuaranteeError.LimitExceeded, "guarantee transcript refusal"
  let short = exportBundle(0, 6).bundleErasureSource.value.layoutSource.value.bundleSource.value
  releaseCycle(short)
  let before = getOccupiedMem()
  for iteration in 0..<1000: releaseCycle(short)
  let after = getOccupiedMem()
  assert before == after, "report cycle ARC release"
  recordArcRelease("jamnp_work_report", 1000, before, after)
  echo "JAMNP-S original work report passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
