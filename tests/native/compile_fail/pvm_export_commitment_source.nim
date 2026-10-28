# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached refinement cannot replace the original completed report identity.

# @@Verification={"group": "nominal", "expected": "ReportIdentity", "early": ["prepareExportCommitment(", "[1] expected: ReportIdentity but got: RefinedPackage"]}

import ../../../src/state/export_commitment as state_export_commitment
import ../../../src/state/refinement_report as state_refinement_report
discard prepareExportCommitment(default(RefinedPackage), default(ExportCommitmentLimits))
