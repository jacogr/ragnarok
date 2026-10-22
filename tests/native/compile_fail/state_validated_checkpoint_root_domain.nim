# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodeValidatedCheckpoint(", "[2] expected: StateRoot but got: StateStoreSnapshot"]}

## Complete snapshots do not implicitly become independently supplied root authority.
import ../../../src/state/[validated_checkpoint, store]
import ../../../src/codec/state_composition
discard decodeValidatedCheckpoint([], default(StateStoreSnapshot), [], default(StateProfile),
    default(StateCheckpointLimits))
