# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "directoryReason"}

## Prepared plan/report storage and result alternatives remain private.
import ../../../src/state/account/review/plan as account_review_plan
var value = default(AccountReviewPlanResult[StateAccountReviewPlan])
discard value.directoryReason
