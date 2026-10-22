# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CurrentStateSerialization", "early": ["reviewCurrentState(", "[1] expected: CurrentStateSerialization but got: StateInventory"]}

## An equal-root detached inventory cannot substitute the original current-bound serialization owner.
import ../../../src/state/[current_review, inventory, account_review_plan]
discard reviewCurrentState(default(StateInventory), AccountReviewPlanLimits())
