# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodePlannedAccountCheckpoint(", "[2] expected: StateRoot but got: seq"]}

## Raw bytes cannot replace an independently selected root identity.
import ../../../src/state/planned/account_checkpoint as planned_account_checkpoint
import ../../../src/codec/state/composition as state_composition
let bytes: seq[byte] = @[]
discard decodePlannedAccountCheckpoint(bytes, bytes, [], StateProfile(),
    PlannedAccountCheckpointLimits())
