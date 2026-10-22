# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: BlockAccumulationGuests but got: PreparedAccumulationCoverage", "early": ["prepareAccumulationAccountStage(", "[1] expected: BlockAccumulationGuests but got: PreparedAccumulationCoverage"]}

## Pure provider coverage cannot replace authenticated block authority.
import ../../../src/state/[accumulation_account_stage, accumulation_coverage]
discard prepareAccumulationAccountStage(default(PreparedAccumulationCoverage), default(AccumulationAccountStageLimits))
