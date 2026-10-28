# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized guards reject missing report owners and wrong-stage details after genuine positive controls.

import std/assertions
import std/cmdline
import ../../src/state/refinement_report as state_refinement_report
import ../../src/state/refinement_bootstrap as state_refinement_bootstrap
import ../../src/state/refinement_outcome as state_refinement_outcome
import ../../src/codec/bounded as codec_bounded
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../support/pvm_report_results
import ../support/pvm_refinement_outcome

proc check(outcome: RefinementReportResult[RefinedPackage], reason: RefinementReportError) =
  ## Confirm the actual alternative without statically specializing the intentional misuse below.
  assert outcome.error == reason
let guest = reportGuest([refinementImmediate(7, 196608), refinementImmediate(8, 3), @[50'u8, 0]])
let source = reportFixture([guest])
let success = reportRun(source, [])
check(success, RefinementReportError.None)
assert success.value.reportInfo.value.blobBytes == 3
var cap = reportLimits()
cap.bootstrap.preimage = ByteLimit(0)
let preparation = reportRun(source, [], cap)
check(preparation, RefinementReportError.BootstrapFailure)
assert preparation.bootstrapError == RefinementBootstrapError.LimitExceeded
cap = reportLimits()
cap.blobs = ByteLimit(2)
let refused = reportRun(source, [], cap)
check(refused, RefinementReportError.LimitExceeded)
cap = reportLimits()
cap.invocation = default(RefinementInvocationLimits)
let invocation = reportRun(source, [], cap)
check(invocation, RefinementReportError.InvocationFailure)
assert invocation.invocationError.error == RefinementInvocationError.BootstrapFailure
let missing = default(RefinementReportResult[RefinedPackage])
check(missing, RefinementReportError.Uninitialized)
case paramStr(1)
of "default": discard missing.value # Default has no completed prefix.
of "refused": discard refused.value # Local retention refusal carries no report.
of "preparation": discard preparation.value # Preparation failure cannot expose an earlier item prefix.
of "invocation": discard invocation.value # Invocation failure likewise has no report owner.
of "success-bootstrap": discard success.bootstrapError # Success has no preparation reason.
of "success-invocation": discard success.invocationError # Success has no nested invocation alternative.
of "wrong-bootstrap": discard invocation.bootstrapError # Stages have distinct reason accessors.
of "wrong-invocation": discard preparation.invocationError # Preparation cannot fabricate execution detail.
of "owner": discard default(RefinedPackage).reportInfo.value # Default owner extraction is guarded.
of "item": discard default(RefinedWorkItem).refinedInfo.value # Default item has no facts.
of "index": discard success.value.reportItem(FetchItemIndex(high(uint64))).value # Index refusal carries no item.
else:
  let failure = reportRun(reportFixture([reportGuest(guest.instructions, 1)]), []).value
  discard failure.reportItem(FetchItemIndex(0)).value.refinedOutput.value # Protocol work errors have no success blob.
