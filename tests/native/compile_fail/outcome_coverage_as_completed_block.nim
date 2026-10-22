# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: CompletedBlockAccumulation but got: PreparedAccumulationCoverage","early":["executionInfo(","[1] expected: CompletedBlockAccumulation but got: PreparedAccumulationCoverage"]}

## Explicit-input coverage cannot alias byte counts, protocol IDs or completed block authority.
import ../../../src/state/[accumulation_coverage, accumulation_execution]
import ../../../src/codec/[bounded, state_accounts]
discard executionInfo(default(PreparedAccumulationCoverage))
