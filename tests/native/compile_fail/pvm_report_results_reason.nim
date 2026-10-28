# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject public result forgery, source rebinding and mixed report retention domains.

# @@Verification={"group": "privacy", "expected": "invocationReason"}

import ../../../src/state/refinement_report as state_refinement_report
var outcome: RefinementReportResult[RefinedPackage]
discard outcome.invocationReason
