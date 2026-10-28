# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodePlannedReviewCheckpoint(", "[2] expected: StateRoot but got: seq"]}

## Raw bytes cannot supply independently selected complete root authority.
import ../../../src/state/planned_review_checkpoint as state_planned_review_checkpoint
import ../../../src/state/economic_profile as state_economic_profile
import ../../../src/codec/state_composition as codec_state_composition
let bytes: seq[byte] = @[]
discard decodePlannedReviewCheckpoint(bytes, bytes, [], StateProfile(), default(
    StateEconomicProfile), PlannedReviewCheckpointLimits())
