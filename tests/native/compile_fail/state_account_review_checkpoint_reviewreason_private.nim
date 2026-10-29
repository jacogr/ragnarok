# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "reviewReason"}

## Caller cannot forge restored review authority or mutate failed stage alternatives.
import ../../../src/state/account/review/checkpoint as account_review_checkpoint
var value = default(AccountReviewCheckpointResult)
discard value.reviewReason
