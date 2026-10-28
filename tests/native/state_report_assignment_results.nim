# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused plans and absent captured credential context cannot expose successful
## payloads.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/state/report_assignments as state_report_assignments
import ../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../src/codec/state_availability as codec_state_availability
if paramStr(1) == "context":
  let missing = default(VerifiedGuaranteeCredentials).verifiedGuaranteeContext
  discard missing.value # No fabricated default clock/population.
else:
  let outcome = if paramStr(1) == "error":
    planReportAssignments(default(VerifiedGuaranteeCredentials), default(AvailabilitySnapshot),
        default(AvailabilityConfig))
  else:
    default(ReportAssignmentResult[ReportAssignmentPlan]) # No fabricated empty successful plan.
  discard outcome.value # Both alternatives must fail success extraction.
