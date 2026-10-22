# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateSupervisionTable", "early": ["joinAccountReview(", "[2] expected: StateSupervisionTable but got: StateEconomicsTable"]}

## Economic observations cannot substitute for complete supervisor decisions.
import ../../../src/state/[account_review, account_invariants, economics_table]
discard joinAccountReview(default(CheckedAccountInvariants), default(StateEconomicsTable), default(StateEconomicsTable))
