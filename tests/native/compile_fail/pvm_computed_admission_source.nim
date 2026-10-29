# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw composed batch cannot replace exact candidate-inclusion authority.

# @@Verification={"group": "nominal", "expected": "IncludedComputedGuarantees", "early": ["admitComputedReports(", "[1] expected: IncludedComputedGuarantees but got: ComputedGuaranteeBatch"]}

import ../../../src/state/computed/[admission as computed_admission, batch as computed_batch]
import ../../../src/state/report/admission as report_admission
discard admitComputedReports(default(ComputedGuaranteeBatch), ReportAdmissionConfig())
