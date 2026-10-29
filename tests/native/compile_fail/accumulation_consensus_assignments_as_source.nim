# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationAuthorization", "early": ["prepareAccumulationConsensus(", "[1] expected: PreparedAccumulationAuthorization but got: ReportAssignmentPlan"]}

## Detached stages, assignments and complete maps cannot replace the authenticated accumulation source.

import ../../../src/state/accumulation/consensus as accumulation_consensus
import ../../../src/state/report/assignments as report_assignments
var source: ReportAssignmentPlan
var limits: AccumulationConsensusLimits
discard prepareAccumulationConsensus(source, limits)
