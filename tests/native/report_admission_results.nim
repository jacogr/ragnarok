# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default, refused and wrong-stage report results cannot expose values or disconnected child
## reasons.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import ../../src/state/[report_admission, block_transition]
let missing = default(BlockTransitionResult)
if paramStr(1) == "profile":
  discard missing.blockTransitionProfile # A default coordinator result has no authenticated profile.
elif paramStr(1) == "owner":
  discard default(AdmittedReports).reportAssignments.value # A default owner cannot yield an assignment candidate.
else:
  let outcome = if paramStr(1) == "default": default(ReportAdmissionResult[AdmittedReports])
    else: planBlockReports(missing, [], default(ReportAdmissionConfig)) # Actual refusal, no forged tag.
  case paramStr(1)
  of "credential": discard outcome.credentialError # Wrong selected child reason.
  of "policy": discard outcome.policyError # No parent-policy stage ran.
  of "history": discard outcome.historyError # No history correction ran.
  of "anchor": discard outcome.anchorError # No anchor stage ran.
  of "package": discard outcome.packageError # No package stage ran.
  of "assignment": discard outcome.assignmentError # No assignment plan exists.
  else: discard outcome.value # Default/refused alternatives expose no successful certificate.
