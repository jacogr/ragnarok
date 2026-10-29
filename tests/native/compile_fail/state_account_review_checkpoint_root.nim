# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodeAccountReviewCheckpoint(", "[2] expected: StateRoot but got: seq"]}

## Raw bytes cannot replace an independently selected root identity.
import ../../../src/state/account/review/checkpoint as account_review_checkpoint
import ../../../src/state/economic_profile
import ../../../src/codec/state/composition as state_composition
let bytes: seq[byte] = @[]
discard decodeAccountReviewCheckpoint(bytes, bytes, [], StateProfile(), default(
    StateEconomicProfile), AccountReviewCheckpointLimits())
