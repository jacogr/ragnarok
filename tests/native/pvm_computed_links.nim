# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized lookup-owner result guards with a genuine independent exporter-wire positive control.

import std/assertions
import std/cmdline
import ../../src/state/computed_links as state_computed_links
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/state/computed_report as state_computed_report
import ../../src/state/report_identity as state_report_identity
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_computed_links
import ../support/pvm_computed_report
import ../support/pvm_computed_report_vectors

proc check[T](outcome: ComputedLinksResult[T], reason: ComputedLinksError) =
  ## Establish the exact alternative before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed links guard control"
let report = prepareComputedReport(computedAvailability(1), ByteLimit(100000)).value
assert report.computedReportBytes.value == @SingleReport, "independent complete exporter control"
let source = linksConsumer([linksPair(report)], repeat = true)
let done = prepareComputedLinks(source, [report], ElementLimit(1))
check(done, ComputedLinksError.None)
assert done.value.computedLinkWitness(ReportLookupIndex(0)).value.computedReportBytes.value ==
    @SingleReport, "retained genuine correspondence control"
let missing = default(ComputedLinksResult[ComputedReportLinks])
let invalid = prepareComputedLinks(default(ComputedGuaranteeTranscript), [], ElementLimit(0))
check(invalid, ComputedLinksError.InvalidSource)
let shape = prepareComputedLinks(source, [], ElementLimit(1))
check(shape, ComputedLinksError.InvalidShape)
let limited = prepareComputedLinks(source, [report], ElementLimit(0))
check(limited, ComputedLinksError.LimitExceeded)
let witness = prepareComputedLinks(source, [default(ComputedWorkReport)], ElementLimit(1))
check(witness, ComputedLinksError.InvalidWitness)
let package = prepareComputedLinks(source, [linksExporter(11)], ElementLimit(1))
check(package, ComputedLinksError.PackageMismatch)
let rootSource = linksConsumer([linksPair(report, wrongRoot = true)])
let root = prepareComputedLinks(rootSource, [report], ElementLimit(1))
check(root, ComputedLinksError.RootMismatch)
case paramStr(1)
of "default": discard missing.value # No completed correspondence in defaults.
of "source": discard invalid.value # No transcript provenance.
of "shape": discard shape.value # No partial or unused witness set.
of "limit": discard limited.value # No retained candidate on local policy refusal.
of "witness": discard witness.value # No default exporter certificate.
of "package": discard package.value # Correct roots cannot substitute unrelated packages.
of "root": discard root.value # Exact keys cannot substitute unrelated roots.
of "count": discard default(ComputedReportLinks).computedLinkCount.value # No default successful empty relation.
of "owner": discard default(ComputedReportLinks).computedLinkSource.value # No invented source transcript.
of "index": discard done.value.computedLinkWitness(ReportLookupIndex(high(
    uint64))).value # Full-width index refusal.
else: discard default(ComputedReportLinks).computedLinkWitness(ReportLookupIndex(
    0)).value # Defaults retain no witnesses.
