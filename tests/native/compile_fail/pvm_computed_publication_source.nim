# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A detached ordinary admission certificate cannot replace computation-bound admission.

# @@Verification={"group": "nominal", "expected": "AdmittedComputedReports", "early": ["prepareComputedPublication(", "[1] expected: AdmittedComputedReports but got: AdmittedReports"]}

import ../../../src/state/computed/publication as computed_publication
import ../../../src/state/report/admission as report_admission
import ../../../src/codec/bounded
discard prepareComputedPublication(default(AdmittedReports), ByteLimit(100000))
