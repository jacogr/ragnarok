# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationStatistics but got: CompletedCurrentAccumulationSequence", "early": ["prepareCurrentAccumulationAccounts(", "[1] expected: PreparedCurrentAccumulationStatistics but got: CompletedCurrentAccumulationSequence"]}

## Timestamp provenance and caller-state boundaries are nominal.
import ../../../src/state/[accumulation_current_accounts, accumulation_accounts,
    accumulation_current_statistics, accumulation_current_driver]
discard prepareCurrentAccumulationAccounts(default(CompletedCurrentAccumulationSequence), default(AccumulationAccountConfig))
