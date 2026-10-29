# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject public result forgery, source rebinding and mixed report retention domains.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/refinement/report as refinement_report
var outcome: RefinementReportResult[RefinedPackage]
discard outcome.completed
