# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized computed-report result guards include independent complete canonical-wire controls.

import std/assertions
import std/cmdline
import ../../src/state/computed_report as state_computed_report
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_computed_report
import ../support/pvm_computed_report_vectors

proc check[T](outcome: ComputedReportResult[T], reason: ComputedReportError) =
  ## Inspect runtime alternatives before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed report guard control"
let source = computedAvailability(0)
let done = prepareComputedReport(source, ByteLimit(100000))
check(done, ComputedReportError.None)
assert done.value.computedReportBytes.value == @EmptyReport, "independent complete report control"
let missing = default(ComputedReportResult[ComputedWorkReport])
let invalid = prepareComputedReport(default(AvailabilityCommitment), ByteLimit(100000))
check(invalid, ComputedReportError.InvalidSource)
let domain = prepareComputedReport(narrowReportSource(), ByteLimit(100000))
check(domain, ComputedReportError.InvalidReport)
let limited = prepareComputedReport(source, ByteLimit(0))
check(limited, ComputedReportError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Defaults contain no complete work report.
of "source": discard invalid.value # Missing original provenance cannot fabricate metadata.
of "domain": discard domain.value # Original configured core/shard bounds cannot be replaced by caller input.
of "limit": discard limited.value # Refused memory policies expose no wire prefix.
of "info": discard default(ComputedWorkReport).computedReportInfo.value # Defaults have no complete metadata.
of "owner": discard default(ComputedWorkReport).computedReportSource.value # Defaults have no original availability source.
else: discard default(ComputedWorkReport).computedReportBytes.value # Defaults cannot invent a successful empty report.
