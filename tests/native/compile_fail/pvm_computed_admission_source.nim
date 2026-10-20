# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw composed batch cannot replace exact candidate-inclusion authority.

# @@Verification={"group": "nominal", "expected": "IncludedComputedGuarantees", "early": ["admitComputedReports(", "[1] expected: IncludedComputedGuarantees but got: ComputedGuaranteeBatch"]}

import ../../../src/state/[computed_admission, computed_batch, report_admission]
discard admitComputedReports(default(ComputedGuaranteeBatch), ReportAdmissionConfig())
