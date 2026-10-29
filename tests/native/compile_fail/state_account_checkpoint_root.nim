# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodeAccountCheckpoint(", "[2] expected: StateRoot but got: seq"]}

## Arbitrary bytes cannot substitute for an independently selected root identity.
import ../../../src/state/account/checkpoint as account_checkpoint
import ../../../src/codec/state/composition as state_composition
let bytes: seq[byte] = @[]
discard decodeAccountCheckpoint(bytes, bytes, [], StateProfile(), AccountCheckpointLimits())
