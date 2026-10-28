# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "checkpointReason"}

## Caller cannot forge restored review authority or mutate failed stage alternatives.
import ../../../src/state/account_review_checkpoint as state_account_review_checkpoint
var value = default(AccountReviewCheckpointResult)
discard value.checkpointReason
