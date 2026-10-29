# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateSupervisionTable", "early": ["joinAccountReview(", "[2] expected: StateSupervisionTable but got: StateEconomicsTable"]}

## Economic observations cannot substitute for complete supervisor decisions.
import ../../../src/state/account/[review as account_review, invariants as account_invariants]
import ../../../src/state/economics_table
discard joinAccountReview(default(CheckedAccountInvariants), default(StateEconomicsTable), default(StateEconomicsTable))
