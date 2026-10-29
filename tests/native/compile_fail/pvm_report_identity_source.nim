# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached refinement sources without original authorization.

# @@Verification={"group": "nominal", "expected": "AuthorizedRefinement", "early": ["prepareReportIdentity(", "[1] expected: AuthorizedRefinement but got: RefinedPackage"]}

import ../../../src/state/report/identity as report_identity
import ../../../src/state/refinement/report as refinement_report
discard prepareReportIdentity(default(RefinedPackage), [], default(ReportIdentityLimits))
