# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw composed batch cannot replace exact candidate-inclusion authority.

# @@Verification={"group": "nominal", "expected": "IncludedComputedGuarantees", "early": ["admitComputedReports(", "[1] expected: IncludedComputedGuarantees but got: ComputedGuaranteeBatch"]}

import ../../../src/state/computed_admission as state_computed_admission
import ../../../src/state/computed_batch as state_computed_batch
import ../../../src/state/report_admission as state_report_admission
discard admitComputedReports(default(ComputedGuaranteeBatch), ReportAdmissionConfig())
