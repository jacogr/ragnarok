# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: AccumulationCoverageIndex but got: ServiceIndex","early":["coverageRowAt(","[2] expected: AccumulationCoverageIndex but got: ServiceIndex"]}

## Explicit-input coverage cannot alias byte counts, protocol IDs or completed block authority.
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    execution as accumulation_execution]
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
discard coverageRowAt(default(PreparedAccumulationCoverage), ServiceIndex(0))
