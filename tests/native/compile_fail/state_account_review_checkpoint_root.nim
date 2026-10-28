# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodeAccountReviewCheckpoint(", "[2] expected: StateRoot but got: seq"]}

## Raw bytes cannot replace an independently selected root identity.
import ../../../src/state/account_review_checkpoint as state_account_review_checkpoint
import ../../../src/state/economic_profile as state_economic_profile
import ../../../src/codec/state_composition as codec_state_composition
let bytes: seq[byte] = @[]
discard decodeAccountReviewCheckpoint(bytes, bytes, [], StateProfile(), default(
    StateEconomicProfile), AccountReviewCheckpointLimits())
