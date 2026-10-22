# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: AccumulationCoverageIndex but got: ServiceIndex","early":["coverageRowAt(","[2] expected: AccumulationCoverageIndex but got: ServiceIndex"]}

## Explicit-input coverage cannot alias byte counts, protocol IDs or completed block authority.
import ../../../src/state/[accumulation_coverage, accumulation_execution]
import ../../../src/codec/[bounded, state_accounts]
discard coverageRowAt(default(PreparedAccumulationCoverage), ServiceIndex(0))
