# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Caller cannot forge composite account authority or rewrite private source/evidence fields.
import ../../../src/state/account_review
var value = default(AccountReviewResult[StateAccountReview])
discard value.status
