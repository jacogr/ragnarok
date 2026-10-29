# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: CompletedBlockAccumulation but got: PreparedAccumulationCoverage","early":["executionInfo(","[1] expected: CompletedBlockAccumulation but got: PreparedAccumulationCoverage"]}

## Explicit-input coverage cannot alias byte counts, protocol IDs or completed block authority.
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    execution as accumulation_execution]
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
discard executionInfo(default(PreparedAccumulationCoverage))
