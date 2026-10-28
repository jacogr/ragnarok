# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized guarded transcript results include a genuine independent complete-wire/message control.

import std/assertions
import std/cmdline
import ../../src/state/computed_report as state_computed_report
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/codec/bounded as codec_bounded
import ../../src/crypto/guarantee as crypto_guarantee
import ../support/pvm_computed_report
import ../support/pvm_computed_report_vectors
import ../support/pvm_computed_guarantee

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after completing and independently validating the original report.
proc check[T](outcome: ComputedGuaranteeResult[T], reason: ComputedGuaranteeError) =
  ## Validate the selected alternative before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed guarantee guard control"
let report = prepareComputedReport(computedAvailability(0), ByteLimit(100000)).value
assert report.computedReportBytes.value == @EmptyReport, "independent complete report control"
let done = prepareComputedGuarantee(report, ByteLimit(100000))
check(done, ComputedGuaranteeError.None)
assert array[45, byte](done.value.computedGuaranteeMessage.value) == expectedGuarantee(EmptyHash), "independent guarantee control"
let missing = default(ComputedGuaranteeResult[ComputedGuaranteeTranscript])
let invalid = prepareComputedGuarantee(default(ComputedWorkReport), ByteLimit(0))
check(invalid, ComputedGuaranteeError.InvalidSource)
let limited = prepareComputedGuarantee(report, ByteLimit(0))
check(limited, ComputedGuaranteeError.LimitExceeded)
reset(1)
let refused = prepareComputedGuarantee(report, ByteLimit(100000))
check(refused, ComputedGuaranteeError.BackendFailure)
case paramStr(1)
of "default": discard missing.value # No invented successful transcript.
of "source": discard invalid.value # No detached report or raw hash substitute.
of "limit": discard limited.value # No bytes on refused local work.
of "backend": discard refused.value # No message after a primitive refusal.
of "report": discard default(ComputedGuaranteeTranscript).computedGuaranteeReport.value # Defaults retain no original report.
else: discard default(ComputedGuaranteeTranscript).computedGuaranteeMessage.value # Defaults have no fixed signing bytes.
