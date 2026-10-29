# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateInventory", "early": ["planAccountReview(", "[1] expected: StateInventory but got: StateStoreSnapshot"]}

## Raw maps cannot substitute for a complete logical inventory.
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/state/[store, economic_profile]
discard planAccountReview(default(StateStoreSnapshot), default(StateEconomicProfile),
    AccountReviewPlanLimits())
