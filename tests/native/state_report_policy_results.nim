# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused policy results cannot expose a successful certificate.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/state/report_policy as state_report_policy
import ../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../src/state/store as state_store
let outcome = if paramStr(1) == "error":
  checkReportPolicy(default(VerifiedGuaranteeCredentials), default(StateStoreSnapshot), default(ReportPolicyConfig))
else:
  default(ReportPolicyResult[PolicyCheckedReports]) # Default contains no fabricated certificate.
discard outcome.value # Both alternatives must fail the success precondition.
